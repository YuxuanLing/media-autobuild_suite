@echo off

set currBat=%~dp0
set currdir=%currBat:~0,-1%
set auto_update_log=%currdir%\auto_update_log.log

@echo Update  Started: %date% %time%     > %auto_update_log%
python "E:\work\home_repos\mirror_fork\fetchGitDependencies.py" -d "D:\work\own_work\wme_bare" -f  "D:\work\own_work\python\fetchWME\full_urls.txt" >> %auto_update_log%
@echo Update  Completed: %date% %time%  >> %auto_update_log%
