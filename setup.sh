#!/usr/bin/env bash
if [[ $# -ne 2 || -z "$1" || -z "$2" ]];then
	echo "用法：$0 \"git 用户名\" \"git 邮箱\"" >&2
	exit 1
fi

git_name="$1"
git_email="$2"

echo "setup.sh 开始运行"
# 打印错误原因并结束脚本
fail() {
    echo "错误：$1" >&2
    exit 1
}

# 读取发行版信息，选择包管理器和 Python 软件包
source /etc/os-release || fail "无法读取 /etc/os-release"

case "$ID" in
    ubuntu)
        package_manager=apt-get
        python_package=python-is-python3
        ;;
    fedora)
        package_manager=dnf
        python_package=python-unversioned-command
        ;;
    *)
        fail "暂不支持 $PRETTY_NAME，目前支持 Ubuntu 和 Fedora"
        ;;
esac

echo "当前系统：$PRETTY_NAME，使用 $package_manager 安装软件"

# $1 是要检查的命令名，$2 是要安装的软件包名
install_tool() {
    local cmd="$1"
    local package="$2"

    if command -v "$cmd"; then
        echo "$cmd 已安装"
    else
        echo "未找到 $cmd，正在安装 $package……"
        sudo "$package_manager" install -y "$package" ||
            fail "安装 $package 失败，请查看上方报错"
    fi
}

# 安装普通工具。后面配置 Docker 仓库时会用到 curl
install_tool git git
install_tool python "$python_package"
install_tool gcc gcc
install_tool curl curl
install_tool tree tree
install_tool nano nano

# 根据发行版，从 Docker 官方仓库安装社区版
install_docker_ce() {
    local repo_url="https://download.docker.com/linux/$ID"
    local status

    if [[ "$ID" == ubuntu ]]; then
        # 查询 docker-ce 本身，避免把之前安装的 docker.io 当成社区版软件包
        status=$(dpkg-query -W -f='${Status}' docker-ce 2>/dev/null)

        if [[ "$status" == "install ok installed" ]]; then
            echo "Docker 社区版已安装"
        else
            echo "正在配置 Docker 官方 APT 仓库……"

            sudo apt-get install -y ca-certificates ||
                fail "安装 CA 证书失败"
            sudo install -d -m 0755 /etc/apt/keyrings ||
                fail "创建密钥目录失败"
            sudo curl -fsSL "$repo_url/gpg" -o /etc/apt/keyrings/docker.asc ||
                fail "下载 Docker 签名公钥失败"
            sudo chmod 0644 /etc/apt/keyrings/docker.asc ||
                fail "设置公钥权限失败"

            # 固定写入同一个文件，重复运行不会追加第二份仓库配置
            sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF || fail "写入 Docker 仓库配置失败"
Types: deb
URIs: $repo_url
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

            sudo apt-get update --error-on=any ||
                fail "更新软件列表失败"
            sudo apt-get install docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin ||
                fail "安装 Docker 社区版失败，请查看上方 APT 提示"
        fi
    else
        # 前面的 case 已经检查过系统，进入这里时就是 Fedora
        if rpm -q docker-ce >/dev/null; then
            echo "Docker 社区版已安装"
        else
            if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
                echo "正在配置 Docker 官方 DNF 仓库……"
                sudo dnf install -y dnf5-plugins ||
                    fail "安装 DNF 插件失败"
                sudo dnf config-manager addrepo \
                    --from-repofile "$repo_url/docker-ce.repo" ||
                    fail "添加 Docker 仓库失败"
            fi

            sudo dnf install docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin ||
                fail "安装 Docker 社区版失败，请查看上方 DNF 提示"
        fi
    fi

    sudo systemctl start docker || fail "Docker 已安装，但服务启动失败"
}

install_docker_ce
