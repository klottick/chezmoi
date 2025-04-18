To set up:

```
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
chezmoi init --apply git@github.com:klottick/chezmoi.git
chsh -s "$(which zsh)"
exec zsh
```
