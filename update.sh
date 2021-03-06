#!/usr/bin/env bash

unset TMUX
echo "Kill current session..."
tmux kill-session -t jekyllserver
echo "Run build"
jekyll clean
jekyll b
echo "Create new session"
tmux new-session -d -s jekyllserver
echo "Start jekyll"
tmux send-keys -t jekyllserver 'jekyll s' C-m
gitout=$(git pull)
echo $gitout
if ! [[ $gitout == *"Already up-to-date"* ]]; then
    echo "Found update!"
fi
jekyll clean
jekyll b