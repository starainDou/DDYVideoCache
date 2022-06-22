Pod::Spec.new do |s|
  # 名称，pod search 搜索的关键词,注意这里一定要和.podspec的名称一样,否则报错
  s.name = "DDYVideoCache"
  # 版本号/库原代码的版本
  s.version = "1.0.0"
  # 简介
  s.summary = "视频缓存[暂时只接管系统下载，以后加预加载]"
  # 项目主页地址
  s.homepage     = "https://github.com/starainDou"
  # 许可证/所采用的授权版本
  s.license = 'MIT'
  # 库的作者
  s.author = { "DDYVideoCache" => "634778311@qq.com" }
  # 项目的地址
  s.source = { :git => "", :tag => s.version }
  # 支持的平台及版本
  s.platform = :ios, "10.0"
  # 是否使用ARC，如果指定具体文件，则具体的问题使用ARC
  s.requires_arc = true
  # 源文件
  s.source_files = 'DDYVideoCache/*{h,m}'

  # 三方依赖
  s.dependency 'FMDB'
  # 使用了第三方静态库 LLVideoPlayer WGAVPlayer
  # s.ios.vendored_library = ''
  # s.ios.vendored_libraries = ''
  s.ios.frameworks = 'MobileCoreServices', 'AVFoundation'
  # “弱引用”所需的framework，多个用逗号隔开
  # s.ios.weak_frameworks = 'UserNotifications'
  # 所需的library，多个用逗号隔开
  # s.ios.libraries = 'z','sqlite3.0','c++','resolv'

end
