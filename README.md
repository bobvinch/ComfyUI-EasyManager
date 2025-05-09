## 丢掉整合包！从此不报错！ComfyUI环境自动管理神器！一键安装ComfyUI环境、节点依赖和模型安装，真正一键启动

### 核心功能
- 一键自动安装ComfyUI环境、节点、依赖和下载模型
- 自动处理依赖冲突
- 自动管理pytorch环境（环境崩90%都是torch环境崩）
- 环境一致性和环境分享，只需要管理4个toml配置文件就能快速复制ComfyUI环境。自己环境复制给别人或者将Windows的环境复制到Linux上
- 高阶：手动锁定依赖版本
- 支持百度网盘模型自动下载
- 其他更多强大功能，后续持续更新

## 使用方法


### Window一键运行

【重要】Windows需要先修改powershell的配置，允许脚本运行，否则会闪退，右键powershell以管理员权限运行，然后输入：
```bash
Set-ExecutionPolicy RemoteSigned
```
再弹出的窗口选择“是”，然后输入Y
克隆脚本：
```bash
# 克隆脚本
git clone https://github.com/bobvinch/ComfyUI-EasyManager.git
```

## 创建一个新的ComfyUI
进入ComfyUI-EasyManager目录下win目录,一键安装及启动:右键`setup.ps1` 使用PowerShell运行

## 管理现有的ComfyUI环境
将ComfyUI-EasyManager目录下win目录下的所有文件，复制到现有的ComfyUI目录的同级目录【目录名必须是ComfyUI】，右键`setup.ps1` 使用PowerShell运行，脚本将自动修复现有环境、安装依赖并启动ComfyUI

#### 仅启动
启动ComfyUI环境：右键`start.ps1` 使用PowerShell运行

#### 安装节点
将节点地址维护到`repos.toml`中，然后运行`setup.ps1`

#### 安装模型
将模型地址维护到`models.toml`中，然后运行`setup.ps1`

#### 安装hugging face仓库-主要针对LLM模型
将仓库地址维护到`repos_hf.toml`中，然后运行`setup.ps1`

#### 更新依赖
右键`install_requirements.ps1` 使用PowerShell运行

#### 初始化基础环境-修复pytorch环境
右键`init_pytorch.ps1` 使用PowerShell运行

### Linux一键运行
```bash
# 克隆脚本
git clone https://github.com/bobvinch/ComfyUI-EasyManager.git
# 将脚本复制到ComfyUI同级目录 或者新建一个空白目录
chmod +x install.sh && ./install.sh

```

### 仅启动
```bash
chmod +x start.sh && ./start.sh
```

### 参数配置
文件目录及说明：
```bash
ComfyUI-EasyManager/   # 项目目录
├── linux/  # Linux 运行脚本
    ├── config.toml  # 配置文件，手动指定Python镜像源、用户token和包版本，请去掉文件名的.example后缀,才会生效
    ├── repos.toml # 插件管理地址配置文件，请去掉文件名的.example后缀,才会生效
    ├── repos_hf.toml # huggingface仓库地址配置文件，请去掉文件名的.example后缀,才会生效
    ├── models.toml # 模型地址配置文件，请去掉文件名的.example后缀,才会生效
    ├── install.sh # 一键安装ComfyUI环境、节点依赖和模型安装
    ├── start.sh # 启动ComfyUI,后接参数，指定端口，如：./start.sh 8188 启动ComfyUI，8188为端口号 
    ├── install_requirements.sh # 安装节点依赖，repos.toml节点更新的时候运行 【可单独运行】
    ├── install_repos_hf.sh # 下载hugging face仓库-repos_hf.toml更新时单独执行 【可单独运行】
    ├── download.sh # 下载模型，model.toml更新时运行 【可单独运行】
    ├── init_pytorch.sh # 初始化基础环境-修复pytorch环境,pytorch环境崩溃时运行 【可单独运行】
    ├── tools.sh # 工具脚本
├── win/ #Windows运行脚本
    ├── config.toml #与linux/config.toml一样
    ├── repos.toml # 与linux/repos.toml一样
    ├── repos_hf.toml  # 与linux/repos.toml一样
    ├── models.toml # 与linux/repos.toml一样
    ├── tools.ps1 # 工具脚本
    ├── setup.ps1 # 【可单独运行】一键安装ComfyUI环境、节点依赖和模型安装
    ├── install_requirements.ps1 # 【可单独运行】安装依赖，repos.toml节点更新的时候运行
    ├── start.ps1 # 【可单独运行】启动ComfyUI
    ├── init_pytorch.ps1 # 【可单独运行】初始化基础环境-修复pytorch环境，pytorch环境崩时运行
    ├── download.ps1 # 【可单独运行】下载模型，model.toml更新时运行
    ├── install_repos_hf.ps1 # 【可单独运行】安装hugging face仓库-主要针对LLM模型，repos_hf.toml更新时单独执行

```
### 脚本更新
在ComfyUI-EasyManager目录下执行以下命令更新脚本
```bash 
git pull
```
然后再将所有的ps1文件复制到ComfyUI的同级目录直接替换原有的脚本文件，后缀为.example的文件可以不需要复制

### 提交贡献及问题反馈交流
如果你有什么难以安装的节点，欢迎大家提issue，或者直接提PR，一起完善脚本，帮助更多人轻松玩转ComfyUI的强大功能，或者加群交流，备注：Github ComfyUI工具：[问题反馈及联系加群](https://work.weixin.qq.com/kfid/kfc1bf83fcf005d3715)