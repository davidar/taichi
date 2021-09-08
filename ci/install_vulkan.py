
import os
def main():
    with open('/etc/lsb-release','r') as f:
        lines = f.readlines()
    distrib_release = lines[1].strip() #either 'DISTRIB_RELEASE=20.04' or 'DISTRIB_RELEASE=18.04'
    version = distrib_release.split('=')[1]
    if version == '20.04':
        cmd = '''
        apt install wget
        wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | apt-key add -
        wget -qO /etc/apt/sources.list.d/lunarg-vulkan-1.2.182-focal.list https://packages.lunarg.com/vulkan/1.2.182/lunarg-vulkan-1.2.182-focal.list
        apt update
        apt install vulkan-sdk
        '''
        os.system(cmd)
    elif version == '18.04':
        cmd = '''
        apt install wget
        wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | apt-key add -
        wget -qO /etc/apt/sources.list.d/lunarg-vulkan-1.2.182-bionic.list https://packages.lunarg.com/vulkan/1.2.182/lunarg-vulkan-1.2.182-bionic.list
        apt update
        apt install vulkan-sdk
        '''
    else:
        raise Exception(f"unrecognized ubuntu version: {version}")

if __name__ == "__main__":
    main()