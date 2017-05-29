#!/usr/bin/env bash

unset TMUX
tmux kill-session -t jekyll
jekyll b
tmux new-session -d -s jekyll
tmux send-keys -t jekyll 'jekyll s' C-m
while [ "true" ]
do
    gitout=$(git pull)
    if ! [[ $gitout == *"Already up-to-date"* ]]; then
        tmux kill-session -t jekyll
        jekyll b
        tmux new-session -d -s jekyll
        tmux send-keys -t jekyll 'jekyll s' C-m
    fi
    sleep 60
done
