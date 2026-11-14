# 重庆理工大学课表

Android 版支持从学校个人课表导入正课，也可用截图导入实验课。课表保存在手机上。

## 准备发布

1. 在 GitHub 建一个独立仓库，只纳入 `cqut_lab_schedule` 目录里的项目文件。若源码仓库是私有的，可以另建一个公开的仓库存放 Release，后续命令里的 `OWNER/REPO` 填发布仓库。
2. 用 JDK 的 `keytool` 创建并备份正式签名密钥。密钥文件放在项目之外，签名凭据写入本机的 `android/key.properties`。密钥、配置和手机导出的个人课表都应保存在本地。

   ```powershell
   keytool -genkeypair -keystore cqut-release.p12 -storetype PKCS12 -alias cqut-release -keyalg RSA -keysize 2048 -validity 10000
   ```

   ```properties
   storeFile=D:/private/cqut-release.p12
   storePassword=你的密钥库密码
   keyAlias=cqut-release
   keyPassword=你的密钥库密码
   ```

3. 在 `pubspec.yaml` 设置版本，例如 `version: 0.2.0+2`。以后每次发布都增加 `+` 后的整数，使用相同的包名和正式签名。

## 生成并上传一次更新

使用安装了 Flutter、Android SDK Build-Tools 和 JDK 17 或更高版本的 PowerShell。让 `flutter`、`java` 在 `PATH` 中可用，或用 `-FlutterCommand` 指定 Flutter 路径，并用 `JAVA_HOME` 指定 Android 构建使用的 JDK。

```powershell
.\scripts\prepare-release.ps1 -Repository 'OWNER/REPO' -Notes '优化课表显示' -AndroidSdk 'D:\SDK'
```

脚本构建正式 APK，把 `cqut-schedule.apk` 和 `update.json` 放在 `build/releases/v0.2.0/`。如果已用相同更新地址构建正式包，也可用 `-ApkPath` 传入包的路径。脚本核对 APK 的包名、版本和签名，并把 APK 的 SHA-256 写入 `update.json`。

在 GitHub 的 **Releases → Draft a new release** 选择同名标签 `v0.2.0`，上传这两个文件后发布为 **Latest release**。App 从 `https://github.com/OWNER/REPO/releases/latest/download/update.json` 检查新版本。版本信息中的 APK 地址指向该版本的固定附件。

## 在手机上验证

1. 安装正式签名的 `0.2.0+2`，导入少量正课和实验课作测试。旧调试版如已有数据，先通过使用原调试签名的过渡版备份，换装正式版后恢复。
2. 将 `pubspec.yaml` 改为 `0.2.1+3`，构建并发布 `v0.2.1`。
3. 在手机上的 `0.2.0` 里点「检查更新」，看到 `0.2.1` 后下载并确认安装。重启后核对版本号和已导入的课表。
4. 分别用日常 Wi-Fi 和流量检查更新，观察安装包能否下载完成。网络慢主要影响下载 APK，查看本地课表可以离线使用。
