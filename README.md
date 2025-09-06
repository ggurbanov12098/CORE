# CORE Installation Guide

*Link to download Ubuntu Server 22.04.5:*  
https://drive.google.com/file/d/159dRBNG0QF0hkKz0x2Ph7w2HsQNrk2yP  

Update and install git *(you won't have it if you install minimal version of Ubuntu Server 22.04.5 with no GUI)*  

```bash
sudo apt update  
sudo apt install git -y
```

Clone repo:  

```bash
git clone https://github.com/ggurbanov12098/CORE.git
```

### After executing `install.sh` reboot ubuntu:

Open directory and make it executable (if it's not):

```bash
cd CORE
chmod +x install.sh
./install.sh
```

Reboot Ubuntu:

```bash
sudo reboot
```

Now, execute `start.sh` in GUI mode (not over ssh) for CORE's User Interface:

```bash
chmod +x ./start.sh
./start.sh
```
