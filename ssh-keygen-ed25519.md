# ssh-keygen-ed25519.md

## 12.22.2024 mdy
 
### in https://github.com/github/docs/blob/main/content/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent.md

1. ssh-keygen -t ed25519 -C "your_email@example.com"
1. First, check to see if your ~/.ssh/config file exists in the default location.
```sh
$ open ~/.ssh/config
> The file /Users/YOU/.ssh/config does not exist.
```
1. If the file doesn't exist, create the file.
```js
touch ~/.ssh/config
vi config
```
1. add: 
```sh
Host github.com
   User XXXXX
   IdentityFile ~/.ssh/id_ed25519
```
1. In windows
```sh
# start the ssh-agent in the background
Get-Service -Name ssh-agent | Set-Service -StartupType Manual
Start-Service ssh-agent
```
1. git --version
1. git config --global user.name "XXXx"
1. git config --global user.email "youremail@yourdomain.com"