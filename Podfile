# Podfile — IMProgram iOS 客户端依赖
# 安装后用 IMProgram.xcworkspace 打开（不要再用 .xcodeproj）。
# 本文件须与 IMProgram.xcodeproj 同目录（仓库根）。
#
#   cd <仓库根>/IMProgram && pod install
#
# 原则：只引入「确实用到」的库。当前仅 FMDB（IMDatabase 本地落库用）。
# 其余按需再加：WebSocket 用系统原生 NSURLSessionWebSocketTask；UI 用原生 AutoLayout；
# HTTP 用 NSURLSession；JSON 手写解析。故 Masonry/AFNetworking/YYModel/SDWebImage 暂不引入，
# 等真正用到对应功能（图片=SDWebImage 等）再加。

platform :ios, '15.0'
use_frameworks! :linkage => :static
inhibit_all_warnings!

target 'IMProgram' do
  pod 'FMDB'         # SQLite 封装（本地消息/会话落库，IMDatabase 用）

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
  # 关闭主工程的脚本沙盒：Xcode 15+ 默认 ENABLE_USER_SCRIPT_SANDBOXING=YES 会拒绝
  # CocoaPods 资源拷贝阶段写文件，导致 "Sandbox: deny file-write-create"。
  installer.aggregate_targets.each do |agg|
    agg.user_project.native_targets.each do |t|
      t.build_configurations.each do |config|
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      end
    end
    agg.user_project.save
  end
end
