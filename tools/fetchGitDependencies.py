#!/usr/bin/python3

import sys
import os
import time
import copy
import subprocess
import tempfile
import optparse
import threading
import urllib
import queue
from threading import Thread
from datetime import datetime
from ftplib import FTP

STARS = "****************************************************"
TAB = "    "
TESTS_BREAK = "#--tests--"
# Global configuration variables which are set by the user in main()
verbose = True


class ThreadOutputInfo:
    """ Holds the console output for a thread of execution """

    def __init__(self, name):
        self.name = name # Name of dependency associated with the thread of execution
        self.msg = "" # Top most message i.e. The reason for logging the info
        self.messages = [] # All the messages to date
        self.errors = [] # All the errors to date
        self.done = False # Whether the thread of execution is finished


    def __str__(self):
        """
        Returns a string representing the message(s) to display on the console
        """

        # Note - messages already contains errors
        if verbose:
            out = ""
            for m in self.messages:
                out += "\n\t" + m

            return out + "\n"

        if self.errors:
            out = ""
            for m in self.errors:
                out += "\n\t" + m

            return out + "\n"

        return self.msg


    def __nonzero__(self):
        """Controls what happens if a consumer checks the bool value of the ThreadOutputInfo."""
        return len(self.errors)


    def copy(self):
        """Make a copy of the object"""
        copy_info = ThreadOutputInfo(self.name)
        copy_info.msg = copy.copy(self.msg)
        copy_info.messages = copy.copy(self.messages)
        copy_info.errors = copy.copy(self.errors)
        copy_info.done = self.done

        return copy_info




class ThreadOutput:
    """
    Stores the console output for a thread of execution.
    For every "log" the output will be queued where it can be accessed safely from another thread.

    """
    def __init__(self, name, threadQueue):
        self.info = ThreadOutputInfo(name)
        self.threadQueue = threadQueue


    def __del__(self):

        """Calls complete when the object is destroyed.
        This means the consumer does not need to remember to manually call complete().

        """

        self.complete()


    def __nonzero__(self):
        """
        Controls what happens if a consumer checks the bool value of the ThreadOutput.

        e.g.    out = ThreadOutput("name", Queue.Queue())
                out.write("My message")

                if out:
                    # won't be hit

                out.err("My error")

                if out:
                    # Will be hit

        """

        return len(self.info.errors)


    def write(self, msg):

        """Log some info from the thread of execution. This may then be accessed from another thread."""

        m = msg.rstrip() # Remove \r\n with rstrip()
        self.info.msg = m
        self.info.messages.append(m)

        # Queue the messages in a thread safe manner. Add a copy to the queue to guarantee the msg will be parsed.
        # Otherwise it could be overridden by the next event. e.g. output.write("msg1") & output.write("msg2") would
        # result in queue [{"name", info(..... msg = "msg2")}, {"name", info(..... msg = "msg2")}) - "msg1" is lost".
        # Also allows the consumer to rely upon __del__() to call complete().
        self.threadQueue.put({self.info.name : self.info.copy()})


    def verbose(self, msg):

        """Log verbose only information."""

        self.info.messages.append(msg.rstrip())

        # Only need to inform observing threads if in verbose mode
        if verbose:
            self.threadQueue.put({self.info.name : self.info.copy()})


    def err(self, msg):

        """Log error information. Errors indicate that the execution should terminate."""

        m = "Error: " + msg.rstrip()
        self.info.errors.append(m)
        self.info.messages.append(m)
        self.threadQueue.put({self.info.name : self.info.copy()})


    def complete(self):

        """Mark the thread of execution as complete. There is no more information to log."""

        if not self.info.done:
            self.info.done = True
            self.threadQueue.put({self.info.name : self.info.copy()})



def _remove_directory( output, directory ):

    """Remove the directory and all its contents.

    There have been multiple build issues stemming from directory removal. They
    occur when the directory is not deleted or only partially deleted.

    This will typically happen when another process is using it. e.g.
          - The user has the directory open
          - The user is editing a file located in the directory
          - TortoiseSVN has a handle to the .svn subdirectory (depends on TortoiseSVN version)

    This can cause a project's build to fail. i.e. Because the wrong files are on disk
    or some files are missing.

    """

    if os.path.exists(directory):

        output.write( "Deleting directory %s" % directory )

        # Build the delete command
        if 'win32' == sys.platform:
            cmd = 'RMDIR ' + directory + ' /s /q'
            ##cmd = 'DIR ' + directory
        else:
            cmd = 'rm -rf ' + directory

        so = subprocess.Popen(cmd, shell=True, stderr=subprocess.PIPE)

        err = False
        process_access_err = False
        for line in so.stderr:
            if not err:
                err = True
                output.err("Failed to delete directory %s" % directory)

            output.err( line )

            if 'win32' == sys.platform and "another process" in line:
                process_access_err = True

        if process_access_err:
            output.err("Fatal - partial delete likely")
            output.err("Possible Cause - user is editing a file in the directory or has the directory opened")
            output.err("Possible Cause - TortiseSvn has a handle to the .svn folder - kill TortoiseProc to resolve - TortoiseProc is used by Show log, Repo-browser, etc")
            output.err("Suggestion - Kill other process & manually delete %s" % directory)

        if not err:
            output.write( "Deleted directory %s" % directory )


def _git_clone_bare(printQueue, url, targetDir):
    output = ThreadOutput(os.path.basename(os.path.normpath(targetDir)), printQueue)
    _remove_directory(output, targetDir)
    output.write( "Git clone bare %s to %s\n" % (url, targetDir) )
    cmd = "git clone --bare " + url + "  " + targetDir
    # print(cmd)

    so = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for line in so.stdout:
        output.write(line)
    for line in so.stderr:
        output.write(line.decode('utf-8'))
    output.write("Git clone bare finished ")


def _read_dependency_file(dependency_file_path, include_breaks = False):
    """
    Reads a dependency file (e.g. dependencyList.txt).
    All comments and empty lines will be removed. Only valid dependency lines will be returned.

    """

    dependencies = []

    try:
        dep_file = open( dependency_file_path )
    except:
        print("Fatal Error: Cannot find the dependencies file - %s" % dependency_file_path, file=sys.stderr);
        sys.exit(1)

    for line in dep_file:
        line = line.strip()
        if line.startswith(TESTS_BREAK) and include_breaks:
            dependencies.append(line)

        if line and not line.startswith('#') and line.startswith('git'):
            dependencies.append(line)

    dep_file.close()
    return dependencies


def _assemble_dependency_list(dependency_list):
    """
    e.g.
        Dependency File
        git@sqbu-github.cisco.com:MARI/adaptation_resilience.git
        git@sqbu-github.cisco.com:WME/libsdp.git

    Will result in an assembled dependency list of

        adaptation_resilience.git     git@sqbu-github.cisco.com:MARI/adaptation_resilience.git
        libsdp.git                    git@sqbu-github.cisco.com:WME/libsdp.git

    """
    dependency_list_dict = {}
    for line in dependency_list:
        name = os.path.basename(os.path.normpath(line))
        dependency_list_dict[name] = line

    #for name in dependency_list_dict:
    #    master_line = dependency_list_dict.get(name)
    #    dependencies[name] = Dependency(dependency_list_dict[name], master_line)
    return dependency_list_dict


def _dots(dotdotdot):
    """ Simple utility to get the .... in-progress indicator."""

    if len(dotdotdot) > 10:
        return "" # Reset

    if len(dotdotdot) > 9:
        return dotdotdot + " "  # Handle a draw issue where the 10th . remains

    return dotdotdot + "."

def _time_lapse( start_time ):

    """Calculate the time that has passed since the start_time and format it to be human readable"""

    current_time = datetime.now()
    elapsed_time = current_time - start_time
    return "%s minutes %s seconds" % (elapsed_time.seconds // 60, elapsed_time.seconds % 60 )

def _wait_on_threads(thread_output_queue, start_time, total_start_time):
    """Waits for the dependency threads to complete execution.
    Based on the result this method will either continue or terminate the script.

    """
    refresh_rate = 1
    dotdotdot = ""
    dependency_output = {}

    # Wait until "this" is the only active thread.
    # If "this" is already the only active thread check that printQueue is not empty.
    # i.e. The threads may finish execution before this point but the code should still
    # print the info to console.
    while threading.active_count() > 1 or not thread_output_queue.empty():
        time.sleep(refresh_rate)

        while not thread_output_queue.empty():
            pair = thread_output_queue.get() # Queue's are thread safe
            key = list(pair.keys())[0]
            value = pair[key]

            if value.done:
                # Thread execution has finished
                dependency_output[key] = value
                # Note - \r causes the last line to be rewritten and only works when used with sys.stdout.write
                sys.stdout.write( ("\r" + TAB + "{0: <35}{1: <10}\n").format(key, value.msg) )
                sys.stdout.flush()

        if True:
            dotdotdot = _dots(dotdotdot)
            sys.stdout.write( "\r{0: <15}{1: <10}".format(_time_lapse(start_time), dotdotdot ) )
            sys.stdout.flush()

    sys.stdout.write( "\rTime Total (%s)\n" % _time_lapse(start_time) )
    sys.stdout.flush()

    # If there are errors the script should terminate
    error_count = 0
    for dep in dependency_output.keys():
        outcome = dependency_output[dep]

        if outcome.errors:
            error_count += 1
            print("\n%s" % dep, file=sys.stderr)
            for error in outcome.errors:
                print((TAB + "%s") % error, file=sys.stderr)

    if error_count > 0:
        print(("\n\n" + STARS + "\n\n%s Error(s) - terminating\n%s\n\n" + STARS + "\n") % ( error_count, _time_lapse(total_start_time) ), file=sys.stderr)
        sys.exit(1)

def _create_dependency_dir( dependencyDir ):
    """
        Creates the "dependencies" directory.
    """
    os.mkdir( dependencyDir )

def _fetch_dependencies(dependencyFile, dependencyDir):
    total_start_time = datetime.now()

    # If the externals directory doesn't exist, create it, and set it to ignore
    if not os.path.exists(dependencyDir):
        _create_dependency_dir(dependencyDir)

    dependency_list = _read_dependency_file(dependencyFile)
    dependency_list_dict = _assemble_dependency_list(dependency_list)
    thread_output_queue = queue.Queue()
    start_time = datetime.now()
    for key in dependency_list_dict.keys():
        if key:
            url = dependency_list_dict[key]
            targetDir = dependencyDir + '\\' + key
            t = Thread(target=_git_clone_bare, args=(thread_output_queue, url , targetDir))
            t.start()

    _wait_on_threads(thread_output_queue, start_time, total_start_time)



def main():
    usage =  ('fetchGitDependencies.py -f dependencyList.txt -d dependencies\n'
              + 'The -f and -d options default to the values above\n\n'
              + "fetchDependencies.py will by default git clone bare of the depfile's directory\n")
    oparser = optparse.OptionParser(usage = usage)
    oparser.add_option('-d', '--dependencyDir', action='store', default=".\\dependencies", help='The directory to place git clone out dependencies.')
    oparser.add_option('-f', '--dependencyFile', action='store', default="depfile.txt", help='The dependency definition file to read.')
    options, _ = oparser.parse_args(sys.argv[1:])

    dependDir = options.dependencyDir
    #dependDir = "D:\\work\\own_work\\python\\fetchWME\\dependencies"
    dependFile = options.dependencyFile
    _fetch_dependencies(dependFile, dependDir)



def print_hi(name):
    # Use a breakpoint in the code line below to debug your script.
    print(f'Hi, {name}')  # Press Ctrl+F8 to toggle the breakpoint.


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    main()
    '''
    targetDir="D:\\work\\own_work\\python\\fetchWME\\"
    targetDir+="AudioWMEDevice.git"
    srcURL="git@sqbu-github.cisco.com:WME/AudioWMEDevice.git"
    dependencyFile="D:\\work\\own_work\\python\\fetchWME\\depfile.txt"
    dependency_list = _read_dependency_file(dependencyFile)
    dependency_list_dict = _assemble_dependency_list(dependency_list)

    thread_output_queue = queue.Queue()
    output = ThreadOutput(os.path.basename(os.path.normpath(targetDir)), thread_output_queue)
    _git_clone_bare(output, srcURL, targetDir)
    output.complete()   
    print(output.info.__str__())

    # Phase 2 - checkout or update the dependencies
    dependencyFile="D:\\work\\own_work\\python\\fetchWME\\depfile.txt"
    dependency_list = _read_dependency_file(dependencyFile)
    dependency_list_dict = _assemble_dependency_list(dependency_list)
    thread_output_queue = queue.Queue()
    start_time = datetime.now()
    for key in dependency_list_dict.keys():
        if key:
            t = Thread(target=_git_clone_bare, args=(thread_output_queue, dependency_list_dict[key], key))
            t.start()

    _wait_on_threads(thread_output_queue, start_time, total_start_time)
    
    '''
    print_hi('Finished')
