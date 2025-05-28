To set up:

```


# Generate SSH key
ssh-keygen -t ed25519

# Add SSH key to GitHub (manual)
cat ~/.ssh/id_ed25519.pub
# → Paste into https://github.com/settings/ssh/new
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
chezmoi init --ssh git@github.com:klottick/chezmoi.git

# Apply dotfiles
chezmoi apply
```
