# 更新日志

## v3.26.10（书源规则引擎专项修复）
- 修复调试功能不可用（用户反馈核心问题）：调试页搜索成功打印简介时 `b.intro!.length` 空简介抛空指针中断整条流程；发现 Tab 忽略输入的 URL、永远抓第一条分类。整页重写——日志改读引擎真实调试日志（请求/响应/规则匹配/异常），新增“原始响应”查看（弹窗展示最近一次抓取文本，超 2 万字截断），发现 Tab 真正按输入 URL 执行 exploreByUrl
- 引擎新增规则级调试日志（最近 120 条环形）：搜索/发现/详情/目录/正文/分页各阶段输出 URL、规则原文、命中元素数、提取结果数、详情字段取值、分页拼接值；新增 lastRawResponse 记录最近响应
- 修复整条规则以 `@js:` 开头时被误切为空（`_splitPostProcess` 把开头位置的 `@js:` 当结尾清洗，导致 selector 变空、JS 求值空脚本返回 null）——原版书源大量 `@js:xxx` 主规则因此全部失效，现仅当 `@js:` 出现在规则中间/末尾才剥离
- 修复 JS 求值返回语义：表达式求值结果被“优先返回 result”覆盖（`@js:result+"|"+site` 只返回原始值），改为返回最后一个表达式值
- 接通书源级字段（此前只存不生效）：Header（JSON 或每行 Key:value，合入请求头，URL 内联 headers 可覆盖）、charset（页面强制编码 > 书源 charset > Content-Type > HTML meta > UTF-8 回退 GBK）、variable（JSON 或每行 key=value，注入全部 JS 求值与模板插值）、checkKeyWord（配置了校验词的书源用该校验词搜索并要求有结果才算有效）
- 校验功能对齐原版：搜索链路由“不抛异常即有效”改为“配置 checkKeyWord 必须搜到结果”

## v3.26.9（功能完整性审计与运行期修复）
- 修复章节表致命缺陷：`book_chapters` 建表用保留字 `"index"` 且缺 start_pos/end_pos/variable 列，与 BookChapter.toMap 写入键不一致，导致本地导入(TXT/EPUB/UMD/MOBI)、离线缓存、保存章节全部运行期崩溃；统一为 chapter_index 列并补齐字段，数据库升级 v6→v7 并自动迁移旧数据
- 修复备份崩溃：默认备份直接把 ReadRecord 对象交给 jsonEncode 会抛异常（无 toJson），改为 toMap 并补全阅读记录的恢复
- 修复缓存管理：清除单本书缓存误调用“清空全部”，且原方法删错表（删 caches 而非章节正文）；新增按书清除 clearBookChapterContent，清空改为置空 book_chapters.content
- 书源引擎接入 Cookie 管理器：请求自动携带同域 Cookie、响应回存 Set-Cookie，修复需要会话接力的书源
- 接通此前“只存不生效”的功能：
  - 实验室 5 个开关全部落地：正文自由选择复制、墨水屏去动画高对比主题、分页估算诊断、加速下载(预缓存并发)、打开应用自动 WebDAV 同步(新增 AutoSyncService)
  - 字典规则（正则替换词典）新增 ContentDictService 并在正文显示前应用
  - 高亮标签规则新增 HighlightService，命中片段以彩色 Text.rich 高亮
  - 下载缓存“预下载章节数”落地：阅读时后台顺序/并发预缓存后续 N 章
  - “模拟阅读”落地：进入阅读页按设置自动翻页；移除无对应子系统的“漫画阅读”空开关
  - WebDAV“同步阅读进度”落地：上传备份时一并上传进度（新增 getAllBookProgress）
  - 首页模块卡片由仅弹提示改为跳转到真实发现书籍列表（新增 ExploreBooksScreen，支持翻页/加入/阅读）
- 移除查询不存在表 search_books 的潜在崩溃死方法 getSearchBooks
- analyze 维持 0 error / 0 warning，9 项单元测试全部通过

## v3.26.8（补全与修复）
- 修复 23 处导致无法编译的错误：重复的 ReadRecord 类型、缺失模型导出、crypto 命名遮蔽、BookChapter 缺 toJson、常量类型错误等
- 重写书源规则引擎，新增统一规则管线 rule_pipeline.dart：
  - 真正接入此前写好但未被使用的 CSS / XPath / JSONPath / 正则 / JS 选择器（原 XPath 分支实际退化为默认规则）
  - 支持原版组合语法：`||`(或)、`&&`(链式)、`@@`(取全部)、`##正则##替换`/`###只取匹配`、结尾 `@js:`、整段 `<js>`、`{{}}` 模板
  - 支持 `@css:/@xpath:/@json:` 前缀、`@text/@html/@href/属性名` 取值后缀
  - 默认 JSoup 语法 class./tag./id./text./children + `.N`/`!N`/`[区间]` 索引
  - XPath 谓词同时支持单/双引号
- 抓取链路补全：目录 nextTocUrl 翻页、正文 nextContentUrl 分页拼接、图片正文保留、相对 URL 解析、发现分类 `:::`/`&&&` 解析对齐
- 清理重复/未用导入与重复 Map 键；新增规则管线单元测试 9 项，全部通过；flutter analyze 0 error / 0 warning
- 二轮清理：移除全部 35 个 warning（非空字段冗余 ??、未用私有字段/死方法、弃用导入、未用循环变量），并让 TTS 语言/引擎设置真正生效

## v3.26.7
- 完整复刻 Legado MD3 风格
- 书架：5种布局/6种排序/分组/多选/书籍菜单
- 书源：网络/剪贴板/本地导入/编辑/调试/校验/域名分组
- 阅读：5Tab设置/38项配置/书签/目录/搜索/翻译/内容编辑
- 发现：书源切换/分类/筛选/排序
- 搜索：多源并发/结果菜单/书源筛选
- RSS：订阅源/文章/收藏
- Web服务：HTTP REST API + WebSocket
- WebDAV：备份/恢复/同步
- 云TTS：8家提供商
- 本地书籍：TXT/EPUB/MOBI/PDF/UMD
- 漫画阅读：连续滚动/翻页
- 角色系统：列表/详情/关系网
- 主题：5种预设/自定义管理
- Clean Architecture 架构
