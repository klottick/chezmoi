To set up:

```


# Generate SSH key
ssh-keygen -t ed25519 -C "github-$(hostname)" -f ~/.ssh/id_github

# Add SSH key to GitHub (manual)
cat ~/.ssh/id_github.pub
# → Paste into https://github.com/settings/ssh/new

sh -c "$(curl -fsLS get.chezmoi.io)" -- init --ssh git@github.com:klottick/chezmoi.git

# Apply dotfiles
chezmoi apply
```
