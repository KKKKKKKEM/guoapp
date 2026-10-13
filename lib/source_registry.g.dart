part of 'models.dart';

const _sourceHongguo = SourceSite(
  'hongguo',
  '红果',
  '短剧 · 漫剧 · AI 剧',
  groupId: 'hongguo',
  groupName: '红果',
  entryName: '红果',
  restricted: false,
  defaultEnabled: true,
  searchMode: 'online',
  searchSuggestions: true,
  metadataFields: <String>['onlineDate'],
);

const _sourceHanxiaoquan = SourceSite(
  'hanxiaoquan',
  '韩小圈',
  '韩剧 · 韩国电影 · 综艺动漫',
  groupId: 'hanxiaoquan',
  groupName: '韩小圈',
  entryName: '韩小圈',
  restricted: false,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceGuipian = SourceSite(
  'guipian',
  '鬼片',
  '鬼片 · 电视剧 · 动漫',
  groupId: 'guipian',
  groupName: '鬼片',
  entryName: '鬼片',
  restricted: false,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceSorani = SourceSite(
  'sorani',
  '青空',
  '番剧 · 剧场动画 · 特摄',
  groupId: 'sorani',
  groupName: '青空',
  entryName: '青空',
  restricted: false,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceHuangdou = SourceSite(
  'huangdou',
  '黄豆',
  '精选短剧',
  groupId: 'huangdou',
  groupName: '黄豆',
  entryName: '黄豆',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'local',
  searchSuggestions: false,
  metadataFields: <String>['heat', 'vip'],
);

const _sourceHuangju = SourceSite(
  'huangju',
  '剧果',
  '热门 · 最新 · 分类短剧',
  groupId: 'huangju',
  groupName: '剧果',
  entryName: '剧果',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceYeguo = SourceSite(
  'yeguo',
  '野果',
  '分类短剧 · 在线搜索',
  groupId: 'yeguo',
  groupName: '野果',
  entryName: '野果',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceDsd = SourceSite(
  'dsd',
  '帝果',
  '分类视频 · 在线搜索',
  groupId: 'dsd',
  groupName: '帝果',
  entryName: '帝果',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'paged',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceHuangguoVideo = SourceSite(
  'huangguo-video',
  '黄果视频',
  '视频剧集',
  groupId: 'huangguo',
  groupName: '黄果',
  entryName: '视频',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'local',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceHuangguoai = SourceSite(
  'huangguoai',
  '黄果 AI',
  'AI 短剧',
  groupId: 'huangguo',
  groupName: '黄果',
  entryName: 'AI',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'local',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _sourceCloudfront = SourceSite(
  'cloudfront',
  '黄果旧版',
  '旧 API 剧库',
  groupId: 'huangguo',
  groupName: '黄果',
  entryName: '旧版',
  restricted: true,
  defaultEnabled: false,
  searchMode: 'local',
  searchSuggestions: false,
  metadataFields: <String>[],
);

const _primarySourceSites = <SourceSite>[
  _sourceHongguo,
  _sourceHanxiaoquan,
  _sourceGuipian,
  _sourceSorani,
];

const _restrictedSourceSites = <SourceSite>[
  _sourceHuangdou,
  _sourceHuangju,
  _sourceYeguo,
  _sourceDsd,
  _sourceHuangguoVideo,
  _sourceHuangguoai,
  _sourceCloudfront,
];

const _defaultSourceSites = <SourceSite>[_sourceHongguo];

const _rankingSourceIDs = <String, String>{
  'dsd-catalog': 'dsd',
  'hongguo-ai': 'hongguo',
  'hongguo-comic': 'hongguo',
  'hongguo-hot': 'hongguo',
  'hongguo-real': 'hongguo',
  'huangdou-all': 'huangdou',
  'huangdou-favorite': 'huangdou',
  'huangdou-finish': 'huangdou',
  'huangdou-mogai': 'huangdou',
  'huangdou-search': 'huangdou',
  'huangguo-hot': 'huangguoai',
  'huangguo-potential': 'huangguoai',
  'huangguo-recommend': 'huangguoai',
  'huangju-hot': 'huangju',
  'huangju-new': 'huangju',
  'yeguo-recommend': 'yeguo',
};
