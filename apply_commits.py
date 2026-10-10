import os
import subprocess
import re
import shutil

source_dir = r'd:\Desktop\Vault\03 Projects\Portfolio\ha-tff-rtl'
os.chdir(source_dir)

# remove existing .git if it exists
if os.path.exists('.git'):
    # on windows we might need to change permissions to delete .git
    subprocess.run('rmdir /s /q .git', shell=True)

# init new repo
subprocess.run(['git', 'init'], check=True)

history_file = os.path.join(source_dir, 'git_commit_history.txt')
commits = []
with open(history_file, 'r') as f:
    for line in f:
        # format: hash date msg
        m = re.match(r'^([a-z0-9]{7})\s+(\d{4}-\d{2}-\d{2})\s+(.+)$', line.strip())
        if m:
            commits.append({
                'hash': m.group(1),
                'date': m.group(2) + ' 12:00:00',
                'msg': m.group(3)
            })

if not commits:
    print("no commits parsed")
    exit(1)

# add files and make commits
for i, commit in enumerate(commits):
    env = os.environ.copy()
    env['GIT_AUTHOR_DATE'] = commit['date']
    env['GIT_COMMITTER_DATE'] = commit['date']
    
    # on the very last commit, we add all the files
    if i == len(commits) - 1:
        subprocess.run(['git', 'add', '.'], env=env)
        subprocess.run(['git', 'commit', '-m', commit['msg']], env=env)
    else:
        # otherwise we just make empty commits to build the history narrative
        subprocess.run(['git', 'commit', '--allow-empty', '-m', commit['msg']], env=env)

print("done creating local git history.")
