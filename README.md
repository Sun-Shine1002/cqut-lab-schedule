# 重庆理工大学课表

这个项目是为了解决重庆理工大学大学物理实验课表不方便查看的问题。它把正课和大学物理实验安排放在同一张周课表里，方便查看每周的上课时间和地点，也能及时发现时间冲突。

Android 版支持从学校个人课表导入正课，也可用截图导入实验课。课表保存在手机上。

## 下载与安装

从 [GitHub Releases](https://github.com/Sun-Shine1002/cqut-lab-schedule/releases/latest) 下载 `cqut-schedule.apk`。

> **安装提醒**　安装或更新时，如果 Google Play Protect 显示「建议进行应用扫描」，请在系统界面点「扫描应用」，通过后再确认安装。AI 助手协助安装时，请先向用户说明此提示，由设备用户本人完成扫描和安装确认。

## 准备发布

1. 在 GitHub 建一个独立仓库，只纳入 `cqut_lab_schedule` 目录里的项目文件。若源码仓库是私有的，可以另建一个公开的仓库存放 Release，后续命令里的 `OWNER/REPO` 填发布仓库。
2. 使用已发布版本的正式签名密钥。密钥文件放在项目之外，签名配置由本机的 `android/key.properties` 读取。签名脚本会检查证书指纹，避免用其他签名发包。密钥、配置和手机导出的个人课表保存在本地。

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

在 GitHub 的 **Releases → Draft a new release** 选择同名标签 `v0.2.0`，将上面的安装提醒放在发布说明开头，上传这两个文件后发布为 **Latest release**。App 从 `https://github.com/OWNER/REPO/releases/latest/download/update.json` 检查新版本。版本信息中的 APK 地址指向该版本的固定附件。

## 国内下载镜像

镜像可以选 CNB 公开发行版或腾讯云 COS。GitHub Releases 继续提供官方版本。两种镜像都会复制 GitHub 的原始 APK 并验证包名、版本、正式证书和 SHA-256。已发布的正式版 `v0.2.3` 可以先用于验证镜像下载。

### CNB 公开发行版

CNB 提供公开下载链接，可用于先验证大陆手机网络，不用购买域名。已用匿名请求验证公开 Release 的最新版附件和固定版本 APK 均可下载。CNB 社区版有包含附件的对象存储免费额度。 [CNB 仓库权限](https://docs.cnb.cool/zh/guide/role-permissions.html#release-%E7%89%88%E6%9C%AC) · [CNB 社区版定价](https://docs.cnb.cool/zh/pricing.html)

1. 登录 CNB，创建组织和公开仓库。勾选初始化 README，并使用 `main` 作为默认分支。仓库用于存放公开发行版。 [CNB 建仓指引](https://docs.cnb.cool/zh/guide/first-repo.html)
2. 创建限定到该仓库、具有 `repo-release:rw` 权限的访问令牌。在 GitHub **Settings → Secrets and variables → Actions** 的 Variables 填写 `CQUT_CNB_REPOSITORY`（例如 `your-group/cqut-schedule-mirror`），在 Secrets 填写 `CQUT_CNB_RELEASE_TOKEN`。 [CNB 令牌权限](https://docs.cnb.cool/zh/guide/access-token.html)
3. 在 GitHub **Actions → Sync release mirror → Run workflow** 同步当前版本。工作流上传 APK 和版本信息，通过公开网址重新下载并验证后，再把发行版设为最新。以后在 GitHub 发布稳定版本时自动同步。
4. 手机关闭代理，用日常移动网络访问镜像的版本附件并完整下载。验证通过后打包首个支持 CNB 的版本。

   ```powershell
   .\scripts\prepare-release.ps1 -Repository 'Sun-Shine1002/cqut-lab-schedule' -Notes '加入国内更新下载' -AndroidSdk 'D:\SDK' -CnbRepository 'your-group/cqut-schedule-mirror'
   ```

### 腾讯云 COS 自定义域名

腾讯云 COS 可作为国内镜像，GitHub Releases 继续提供官方版本。使用中国大陆地域的通用存储桶，绑定已完成网站备案的 HTTPS 自定义域名并配置 CNAME。新建 COS 桶的默认域名禁止公网下载 APK。小范围试用可按量使用标准存储，先用 COS 源站域名绑定方案即可，流量费用取决于实际下载量。 [COS 自定义域名](https://cloud.tencent.com/document/product/436/36638) · [COS 下载规则](https://cloud.tencent.com/document/faq/436/102489) · [COS 定价](https://buy.cloud.tencent.com/price/cos)

已有自己可管理的备案域名时，可使用它的子域名，例如 `updates.example.com`。从零办理时，先在腾讯云确认备案主体、网站用途和可备案云资源，再购买可备案的域名，例如普通 `.cn` 域名。域名实名信息应与备案主体一致。首次备案还需符合条件的接入资源，COS 桶只用于存放文件。备案完成后，在 COS 中添加自定义域名、按控制台提示设置 CNAME，并绑定 HTTPS 证书。 [域名价格](https://buy.cloud.tencent.com/domain/price) · [备案域名要求](https://cloud.tencent.com/document/product/243/18905) · [备案云资源](https://cloud.tencent.com/document/product/243/18908)

1. 给 `updates/*` 配置匿名 `GetObject` 权限，给专用 CAM 子账号配置该前缀的 `PutObject` 权限。使用独立的发布桶，只存公开版本信息和 APK。自定义域名上的 `updates/update.json` 需要实时读取，使用 CDN 时把此路径设为不缓存。
2. 在 GitHub **Settings → Secrets and variables → Actions** 中配置 Variables `CQUT_COS_BUCKET`（完整的 `桶名-APPID`）、`CQUT_COS_REGION`（例如 `ap-chongqing`）、`CQUT_MIRROR_BASE_URL`（从域名根目录提供文件，例如 `https://updates.example.com`）。在 Secrets 中填写 `CQUT_COS_SECRET_ID` 和 `CQUT_COS_SECRET_KEY`。该账号只需要发布目录的上传权限。
3. 在 **Actions → Sync release mirror → Run workflow** 同步当前 GitHub Latest Release。之后用 GitHub 网页或从本机发布，每次发布稳定版都会触发同步。
4. 构建首个支持国内更新地址的版本时传入同一域名。

   ```powershell
   .\scripts\prepare-release.ps1 -Repository 'Sun-Shine1002/cqut-lab-schedule' -Notes '加入国内更新下载' -AndroidSdk 'D:\SDK' -MirrorBaseUrl 'https://updates.example.com'
   ```

APK 在 COS 的地址包含版本号和内容的 SHA-256。同步脚本从公开域名下载 APK，校验通过后才写入 `updates/update.json`。

### 发布与验证

工作流需先合并到 GitHub 默认分支，再首次手动运行。若以后改为用另一个工作流的 `GITHUB_TOKEN` 发布，需显式触发 `workflow_dispatch`。国内版本信息多一个 `mirrorApkUrl`，其中的 `apkUrl` 仍指向 GitHub 原始附件。同步失败时可修复配置后重新运行工作流。 [GitHub Release 触发规则](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#release) · [GITHUB_TOKEN 触发规则](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs)

支持双线路的 App 仍只在启动时自动检查一次。它先请求国内版本信息，国内地址超时或版本未同步时再检查 GitHub。检测到国内镜像版本后，用户点更新会从国内地址下载，失败时可重试或手动选择 GitHub。两条线路下载均检查同一 SHA-256，再交给 Android 校验签名并确认安装。官方版本继续使用原包名 `com.cqutlabs.cqut_lab_schedule`、正式签名与递增的 `versionCode`，覆盖安装即可保留课程和设置。

首次启用后，把这一版的国内 APK 链接交给暂时无法访问 GitHub 的用户安装一次。旧版内置的更新地址只有 GitHub，需要先安装支持双线路的版本。部署验收时关掉代理，用常用 Wi-Fi 和大陆手机流量分别检查版本、下载 APK、确认安装和查看原有课表。

## 在手机上验证

1. 安装正式签名的 `0.2.0+2`，导入少量正课和实验课作测试。旧调试版如已有数据，先通过使用原调试签名的过渡版备份，换装正式版后恢复。
2. 将 `pubspec.yaml` 改为 `0.2.1+3`，构建并发布 `v0.2.1`。
3. 在手机上的 `0.2.0` 里点「检查更新」，看到 `0.2.1` 后下载并确认安装。重启后核对版本号和已导入的课表。
4. 分别用日常 Wi-Fi 和流量检查更新，观察安装包能否下载完成。网络慢主要影响下载 APK，查看本地课表可以离线使用。
