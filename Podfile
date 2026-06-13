# Podfile — IMProgram iOS 客户端依赖
# 安装后用 IMProgram.xcworkspace 打开（不要再用 .xcodeproj）。
# 本文件须与 IMProgram.xcodeproj 同目录（仓库根）。
#
#   cd <仓库根>/IMProgram && pod install
#
# 注意：当前代码未依赖任何 Pod（WebSocket 用系统原生），不装 Pod 也能用 .xcodeproj 直接编译运行。
# 说明：WebSocket 长连接用系统原生 NSURLSessionWebSocketTask 实现（见 IMSocketManager），
# 部署目标 iOS 26.2 下无需 SocketRocket；这里只引入 UI/存储/网络等确有价值的三方库。

platform :ios, '15.0'
use_frameworks! :linkage => :static
inhibit_all_warnings!

target 'IMProgram' do
  pod 'Masonry'      # 纯代码 AutoLayout
  pod 'FMDB'         # SQLite 封装（本地消息/会话缓存）
  pod 'SDWebImage'   # 图片加载缓存
  pod 'YYModel'      # JSON ↔ Model
  pod 'AFNetworking' # HTTP（登录/历史/上传）

  target 'IMProgramTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
