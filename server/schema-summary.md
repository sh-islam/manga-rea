## Query
  restoreStatus(id:String!): BackupRestoreStatus
  validateBackup(input:ValidateBackupInput!): ValidateBackupResult!
  categories(condition:CategoryConditionInput, filter:CategoryFilterInput, order:[CategoryOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): CategoryNodeList!
  category(id:Int!): CategoryType!
  chapter(id:Int!): ChapterType!
  chapters(condition:ChapterConditionInput, filter:ChapterFilterInput, order:[ChapterOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): ChapterNodeList!
  downloadStatus: DownloadStatus!
  extension(pkgName:String!): ExtensionType!
  extensions(condition:ExtensionConditionInput, filter:ExtensionFilterInput, order:[ExtensionOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): ExtensionNodeList!
  extensionStore(indexUrl:String!): ExtensionStoreType!
  extensionStores(condition:ExtensionStoreConditionInput, filter:ExtensionStoreFilterInput, order:[ExtensionStoreOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): ExtensionStoreNodeList!
  aboutServer: AboutServerPayload!
  aboutWebUI: AboutWebUI!
  checkForServerUpdates: [CheckForServerUpdatesPayload!]!
  checkForWebUIUpdate: WebUIUpdateCheck!
  getWebUIUpdateStatus: WebUIUpdateStatus!
  koSyncStatus: KoSyncStatusPayload!
  manga(id:Int!): MangaType!
  mangas(condition:MangaConditionInput, filter:MangaFilterInput, order:[MangaOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): MangaNodeList!
  meta(key:String!): GlobalMetaType!
  metas(condition:MetaConditionInput, filter:MetaFilterInput, order:[MetaOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): GlobalMetaNodeList!
  settings: SettingsType!
  source(id:LongString!): SourceType!
  sources(condition:SourceConditionInput, filter:SourceFilterInput, order:[SourceOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): SourceNodeList!
  lastSyncStatus: SyncStatus
  searchTracker(input:SearchTrackerInput!): SearchTrackerPayload!
  trackRecord(id:Int!): TrackRecordType!
  trackRecords(condition:TrackRecordConditionInput, filter:TrackRecordFilterInput, order:[TrackRecordOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): TrackRecordNodeList!
  tracker(id:Int!): TrackerType!
  trackers(condition:TrackerConditionInput, order:[TrackerOrderInput!], before:Cursor, after:Cursor, first:Int, last:Int, offset:Int): TrackerNodeList!
  lastUpdateTimestamp: LastUpdateTimestampPayload!
  libraryUpdateStatus: LibraryUpdateStatus!
  updateStatus: UpdateStatus!

## Mutation
  createBackup(input:CreateBackupInput): CreateBackupPayload!
  restoreBackup(input:RestoreBackupInput!): RestoreBackupPayload!
  createCategory(input:CreateCategoryInput!): CreateCategoryPayload
  deleteCategory(input:DeleteCategoryInput!): DeleteCategoryPayload
  deleteCategoryMeta(input:DeleteCategoryMetaInput!): DeleteCategoryMetaPayload
  deleteCategoryMetas(input:DeleteCategoryMetasInput!): DeleteCategoryMetasPayload
  setCategoryMeta(input:SetCategoryMetaInput!): SetCategoryMetaPayload
  setCategoryMetas(input:SetCategoryMetasInput!): SetCategoryMetasPayload
  updateCategories(input:UpdateCategoriesInput!): UpdateCategoriesPayload
  updateCategory(input:UpdateCategoryInput!): UpdateCategoryPayload
  updateCategoryOrder(input:UpdateCategoryOrderInput!): UpdateCategoryOrderPayload
  updateMangaCategories(input:UpdateMangaCategoriesInput!): UpdateMangaCategoriesPayload
  updateMangasCategories(input:UpdateMangasCategoriesInput!): UpdateMangasCategoriesPayload
  deleteChapterMeta(input:DeleteChapterMetaInput!): DeleteChapterMetaPayload
  deleteChapterMetas(input:DeleteChapterMetasInput!): DeleteChapterMetasPayload
  fetchChapterPages(input:FetchChapterPagesInput!): FetchChapterPagesPayload
  fetchChapters(input:FetchChaptersInput!): FetchChaptersPayload
  setChapterMeta(input:SetChapterMetaInput!): SetChapterMetaPayload
  setChapterMetas(input:SetChapterMetasInput!): SetChapterMetasPayload
  updateChapter(input:UpdateChapterInput!): UpdateChapterPayload
  updateChapters(input:UpdateChaptersInput!): UpdateChaptersPayload
  clearDownloader(input:ClearDownloaderInput!): ClearDownloaderPayload
  deleteDownloadedChapter(input:DeleteDownloadedChapterInput!): DeleteDownloadedChapterPayload
  deleteDownloadedChapters(input:DeleteDownloadedChaptersInput!): DeleteDownloadedChaptersPayload
  dequeueChapterDownload(input:DequeueChapterDownloadInput!): DequeueChapterDownloadPayload
  dequeueChapterDownloads(input:DequeueChapterDownloadsInput!): DequeueChapterDownloadsPayload
  enqueueChapterDownload(input:EnqueueChapterDownloadInput!): EnqueueChapterDownloadPayload
  enqueueChapterDownloads(input:EnqueueChapterDownloadsInput!): EnqueueChapterDownloadsPayload
  reorderChapterDownload(input:ReorderChapterDownloadInput!): ReorderChapterDownloadPayload
  reorderChapterDownloads(input:ReorderChapterDownloadsInput!): ReorderChapterDownloadPayload
  startDownloader(input:StartDownloaderInput!): StartDownloaderPayload
  stopDownloader(input:StopDownloaderInput!): StopDownloaderPayload
  fetchExtensions(input:FetchExtensionsInput!): FetchExtensionsPayload
  installExternalExtension(input:InstallExternalExtensionInput!): InstallExternalExtensionPayload
  updateExtension(input:UpdateExtensionInput!): UpdateExtensionPayload
  updateExtensions(input:UpdateExtensionsInput!): UpdateExtensionsPayload
  addExtensionStore(input:AddExtensionStoreInput!): AddExtensionStorePayload
  removeExtensionStore(input:RemoveExtensionStoreInput!): RemoveExtensionStorePayload
  clearCachedImages(input:ClearCachedImagesInput!): ClearCachedImagesPayload!
  resetWebUIUpdateStatus: WebUIUpdateStatus
  updateWebUI(input:WebUIUpdateInput!): WebUIUpdatePayload
  connectKoSyncAccount(input:ConnectKoSyncAccountInput!): KoSyncConnectPayload!
  logoutKoSyncAccount(input:LogoutKoSyncAccountInput!): LogoutKoSyncAccountPayload!
  pullKoSyncProgress(input:PullKoSyncProgressInput!): PullKoSyncProgressPayload
  pushKoSyncProgress(input:PushKoSyncProgressInput!): PushKoSyncProgressPayload
  deleteMangaMeta(input:DeleteMangaMetaInput!): DeleteMangaMetaPayload
  deleteMangaMetas(input:DeleteMangaMetasInput!): DeleteMangaMetasPayload
  fetchManga(input:FetchMangaInput!): FetchMangaPayload
  fetchMangaAndChapters(input:FetchMangaAndChaptersInput!): FetchMangaAndChaptersPayload
  setMangaMeta(input:SetMangaMetaInput!): SetMangaMetaPayload
  setMangaMetas(input:SetMangaMetasInput!): SetMangaMetasPayload
  updateManga(input:UpdateMangaInput!): UpdateMangaPayload
  updateMangas(input:UpdateMangasInput!): UpdateMangasPayload
  deleteGlobalMeta(input:DeleteGlobalMetaInput!): DeleteGlobalMetaPayload
  deleteGlobalMetas(input:DeleteGlobalMetasInput!): DeleteGlobalMetasPayload
  setGlobalMeta(input:SetGlobalMetaInput!): SetGlobalMetaPayload
  setGlobalMetas(input:SetGlobalMetasInput!): SetGlobalMetasPayload
  resetSettings(input:ResetSettingsInput!): ResetSettingsPayload!
  setSettings(input:SetSettingsInput!): SetSettingsPayload!
  startSync(input:StartSyncInput!): StartSyncPayload!
  deleteSourceMeta(input:DeleteSourceMetaInput!): DeleteSourceMetaPayload
  deleteSourceMetas(input:DeleteSourceMetasInput!): DeleteSourceMetasPayload
  fetchSourceManga(input:FetchSourceMangaInput!): FetchSourceMangaPayload
  setSourceMeta(input:SetSourceMetaInput!): SetSourceMetaPayload
  setSourceMetas(input:SetSourceMetasInput!): SetSourceMetasPayload
  updateSourcePreference(input:UpdateSourcePreferenceInput!): UpdateSourcePreferencePayload
  bindTrack(input:BindTrackInput!): BindTrackPayload!
  bindTrackRecord(input:BindTrackRecordInput!): BindTrackRecordPayload
  fetchTrack(input:FetchTrackInput!): FetchTrackPayload!
  loginTrackerCredentials(input:LoginTrackerCredentialsInput!): LoginTrackerCredentialsPayload!
  loginTrackerOAuth(input:LoginTrackerOAuthInput!): LoginTrackerOAuthPayload!
  logoutTracker(input:LogoutTrackerInput!): LogoutTrackerPayload!
  trackProgress(input:TrackProgressInput!): TrackProgressPayload
  unbindTrack(input:UnbindTrackInput!): UnbindTrackPayload!
  updateTrack(input:UpdateTrackInput!): UpdateTrackPayload!
  updateCategoryManga(input:UpdateCategoryMangaInput!): UpdateCategoryMangaPayload
  updateLibrary(input:UpdateLibraryInput!): UpdateLibraryPayload
  updateLibraryManga(input:UpdateLibraryMangaInput!): UpdateLibraryMangaPayload
  updateStop(input:UpdateStopInput!): UpdateStopPayload!
  login(input:LoginInput!): LoginPayload!
  refreshToken(input:RefreshTokenInput!): RefreshTokenPayload!
  clearCookiesAndCache(input:ClearCookiesAndCacheInput): ClearCookiesAndCachePayload!

## Subscription
  downloadChanged: DownloadStatus!
  downloadStatusChanged(input:DownloadChangedInput!): DownloadUpdates!
  webUIUpdateStatusChange: WebUIUpdateStatus!
  syncStatusChanged: SyncStatus!
  libraryUpdateStatusChanged(input:LibraryUpdateStatusChangedInput!): UpdaterUpdates!
  updateStatusChanged: UpdateStatus!

## MangaType
  artist: String
  author: String
  chaptersLastFetchedAt: LongString
  description: String
  genre: [String!]!
  id: Int!
  inLibrary: Boolean!
  inLibraryAt: LongString!
  initialized: Boolean!
  lastFetchedAt: LongString
  realUrl: String
  sourceId: LongString!
  status: MangaStatus!
  thumbnailUrl: String
  thumbnailUrlLastFetched: LongString
  title: String!
  updateStrategy: UpdateStrategy!
  url: String!
  age: LongString
  bookmarkCount: Int!
  categories: CategoryNodeList!
  chapters: ChapterNodeList!
  chaptersAge: LongString
  downloadCount: Int!
  firstUnreadChapter: ChapterType
  hasDuplicateChapters: Boolean!
  highestNumberedChapter: ChapterType
  lastReadChapter: ChapterType
  latestFetchedChapter: ChapterType
  latestReadChapter: ChapterType
  latestUploadedChapter: ChapterType
  meta: [MangaMetaType!]!
  source: SourceType
  trackRecords: TrackRecordNodeList!
  unreadCount: Int!

## ChapterType
  chapterNumber: Float!
  fetchedAt: LongString!
  id: Int!
  isBookmarked: Boolean!
  isDownloaded: Boolean!
  isRead: Boolean!
  lastPageRead: Int!
  lastReadAt: LongString!
  mangaId: Int!
  name: String!
  pageCount: Int!
  realUrl: String
  scanlator: String
  sourceOrder: Int!
  uploadDate: LongString!
  url: String!
  manga: MangaType!
  meta: [ChapterMetaType!]!

## SourceType
  baseUrl: String
  contentWarning: ContentWarning!
  displayName: String!
  homeUrl: String
  iconUrl: String!
  id: LongString!
  isConfigurable: Boolean!
  isNsfw: Boolean!
  lang: String!
  name: String!
  supportsLatest: Boolean!
  extension: ExtensionType!
  filters: [Filter!]!
  manga: MangaNodeList!
  meta: [SourceMetaType!]!
  preferences: [Preference!]!

## ExtensionType
  apkName: String
  apkUrl: String
  contentWarning: ContentWarning!
  extensionLib: String
  hasUpdate: Boolean!
  iconUrl: String!
  isInstalled: Boolean!
  isNsfw: Boolean!
  isObsolete: Boolean!
  jarUrl: String
  lang: String!
  name: String!
  pkgName: String!
  repo: String
  storeIndexUrl: String
  versionCode: Int!
  versionCodeLong: LongString!
  versionName: String!
  extensionStore: ExtensionStoreType
  source: SourceNodeList!

## ExtensionRepoType: (absent)

## CategoryType
  default: Boolean!
  id: Int!
  includeInDownload: IncludeOrExclude!
  includeInUpdate: IncludeOrExclude!
  isDefaultCategory: Boolean!
  name: String!
  order: Int!
  mangas: MangaNodeList!
  meta: [CategoryMetaType!]!

## DownloadType
  position: Int!
  progress: Float!
  state: DownloadState!
  tries: Int!
  chapter: ChapterType!
  manga: MangaType!

## DownloadStatus
  queue: [DownloadType!]!
  state: DownloaderState!

## DownloadState
  enum: QUEUED DOWNLOADING FINISHED ERROR

## SettingsType
  authMode: AuthMode!
  authPassword: String!
  authUsername: String!
  autoBackupIncludeCategories: Boolean!
  autoBackupIncludeChapters: Boolean!
  autoBackupIncludeClientData: Boolean!
  autoBackupIncludeHistory: Boolean!
  autoBackupIncludeManga: Boolean!
  autoBackupIncludeServerSettings: Boolean!
  autoBackupIncludeTracking: Boolean!
  autoDownloadAheadLimit: Int!
  autoDownloadIgnoreReUploads: Boolean!
  autoDownloadNewChapters: Boolean!
  autoDownloadNewChaptersLimit: Int!
  backupInterval: Int!
  backupPath: String!
  backupTTL: Int!
  backupTime: String!
  basicAuthEnabled: Boolean!
  basicAuthPassword: String!
  basicAuthUsername: String!
  databasePassword: String!
  databaseType: DatabaseType!
  databaseUrl: String!
  databaseUsername: String!
  debugLogsEnabled: Boolean!
  downloadAsCbz: Boolean!
  downloadConversions: [SettingsDownloadConversionType!]!
  downloadsPath: String!
  electronPath: String!
  excludeCompleted: Boolean!
  excludeEntryWithUnreadChapters: Boolean!
  excludeNotStarted: Boolean!
  excludeUnreadChapters: Boolean!
  extensionRepos: [String!]!
  flareSolverrAsResponseFallback: Boolean!
  flareSolverrEnabled: Boolean!
  flareSolverrSessionName: String!
  flareSolverrSessionTtl: Int!
  flareSolverrTimeout: Int!
  flareSolverrUrl: String!
  globalUpdateInterval: Float!
  gqlDebugLogsEnabled: Boolean!
  initialOpenInBrowserEnabled: Boolean!
  ip: String!
  jwtAudience: String!
  jwtRefreshExpiry: Duration!
  jwtTokenExpiry: Duration!
  kcefEnabled: Boolean!
  koreaderSyncChecksumMethod: KoreaderSyncChecksumMethod!
  koreaderSyncDeviceId: String!
  koreaderSyncPercentageTolerance: Float!
  koreaderSyncServerUrl: String!
  koreaderSyncStrategy: KoreaderSyncLegacyStrategy!
  koreaderSyncStrategyBackward: KoreaderSyncConflictStrategy!
  koreaderSyncStrategyForward: KoreaderSyncConflictStrategy!
  koreaderSyncUserkey: String!
  koreaderSyncUsername: String!
  localSourcePath: String!
  maxLogFileSize: String!
  maxLogFiles: Int!
  maxLogFolderSize: String!
  maxSourcesInParallel: Int!
  opdsCbzMimetype: CbzMediaType!
  opdsChapterSortOrder: SortOrder!
  opdsEnablePageReadProgress: Boolean!
  opdsItemsPerPage: Int!
  opdsMarkAsReadOnDownload: Boolean!
  opdsShowOnlyDownloadedChapters: Boolean!
  opdsShowOnlyUnreadChapters: Boolean!
  opdsSkipChapterMetadataFeed: Boolean!
  opdsUseBinaryFileSizes: Boolean!
  port: Int!
  serveConversions: [SettingsDownloadConversionType!]!
  socksProxyEnabled: Boolean!
  socksProxyHost: String!
  socksProxyPassword: String!
  socksProxyPort: String!
  socksProxyUsername: String!
  socksProxyVersion: Int!
  syncDataCategories: Boolean!
  syncDataChapters: Boolean!
  syncDataHistory: Boolean!
  syncDataManga: Boolean!
  syncDataTracking: Boolean!
  syncInterval: Duration!
  syncYomiApiKey: String!
  syncYomiEnabled: Boolean!
  syncYomiHost: String!
  systemTrayEnabled: Boolean!
  updateMangas: Boolean!
  useHikariConnectionPool: Boolean!
  webUIChannel: WebUIChannel!
  webUIFlavor: WebUIFlavor!
  webUIInterface: WebUIInterface!
  webUIUpdateCheckInterval: Float!

## MangaStatus
  enum: UNKNOWN ONGOING COMPLETED LICENSED PUBLISHING_FINISHED CANCELLED ON_HIATUS

## FilterType: (absent)

## SourcePreferenceType: (absent)

## ChapterConditionInput
  chapterNumber: Float
  fetchedAt: LongString
  id: Int
  isBookmarked: Boolean
  isDownloaded: Boolean
  isRead: Boolean
  lastPageRead: Int
  lastReadAt: LongString
  mangaId: Int
  name: String
  pageCount: Int
  realUrl: String
  scanlator: String
  sourceOrder: Int
  uploadDate: LongString
  url: String

## MangaConditionInput
  artist: String
  author: String
  categoryIds: [Int!]
  chaptersLastFetchedAt: LongString
  description: String
  genre: [String!]
  id: Int
  inLibrary: Boolean
  inLibraryAt: LongString
  initialized: Boolean
  lastFetchedAt: LongString
  realUrl: String
  sourceId: LongString
  status: MangaStatus
  thumbnailUrl: String
  title: String
  url: String

## FetchSourceMangaInput
  clientMutationId: String
  filters: [FilterChangeInput!]
  page: Int!
  query: String
  source: LongString!
  type: FetchSourceMangaType!

## FetchSourceMangaType
  enum: SEARCH POPULAR LATEST

## LoginInput
  clientMutationId: String
  password: String!
  username: String!

## LoginPayload
  accessToken: String!
  clientMutationId: String
  refreshToken: String!

## TrackRecordType
  finishDate: LongString!
  id: Int!
  lastChapterRead: Float!
  libraryId: LongString
  mangaId: Int!
  private: Boolean!
  remoteId: LongString!
  remoteUrl: String!
  score: Float!
  startDate: LongString!
  status: Int!
  title: String!
  totalChapters: Int!
  trackerId: Int!
  displayScore: String!
  manga: MangaType!
  tracker: TrackerType!

## BackupRestoreStatus
  mangaProgress: Int!
  state: BackupRestoreState!
  totalManga: Int!

## GlobalMetaType
  key: String!
  value: String!

## SortOrder
  enum: ASC DESC ASC_NULLS_FIRST DESC_NULLS_FIRST ASC_NULLS_LAST DESC_NULLS_LAST

## MangaOrderBy
  enum: ID TITLE IN_LIBRARY_AT LAST_FETCHED_AT

## ChapterOrderBy
  enum: ID SOURCE_ORDER NAME UPLOAD_DATE CHAPTER_NUMBER LAST_READ_AT FETCHED_AT

## SourceMetaType
  key: String!
  sourceId: LongString!
  value: String!
  source: SourceType!

## PageType: (absent)

## FetchChapterPagesPayload
  chapter: ChapterType!
  clientMutationId: String
  pages: [String!]!
  syncConflict: SyncConflictInfoType

## UpdateStatus
  completeJobs: UpdateStatusType!
  failedJobs: UpdateStatusType!
  isRunning: Boolean!
  pendingJobs: UpdateStatusType!
  runningJobs: UpdateStatusType!
  skippedCategories: UpdateStatusCategoryType!
  skippedJobs: UpdateStatusType!
  updatingCategories: UpdateStatusCategoryType!

## LibraryUpdateStatus
  categoryUpdates: [CategoryUpdateType!]!
  jobsInfo: UpdaterJobsInfoType!
  mangaUpdates: [MangaUpdateType!]!

## MangaNodeList
  edges: [MangaEdge!]!
  nodes: [MangaType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## ChapterNodeList
  edges: [ChapterEdge!]!
  nodes: [ChapterType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## SourceNodeList
  edges: [SourceEdge!]!
  nodes: [SourceType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## ExtensionNodeList
  edges: [ExtensionEdge!]!
  nodes: [ExtensionType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## DownloadNodeList
  edges: [DownloadEdge!]!
  nodes: [DownloadType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## CategoryNodeList
  edges: [CategoryEdge!]!
  nodes: [CategoryType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## ExtensionStoreType
  badgeLabel: String!
  contactDiscord: String
  contactWebsite: String!
  extensionListUrl: String
  indexUrl: String!
  isLegacy: Boolean!
  name: String!
  signingKey: String!
  extensions: ExtensionNodeList!

## ExtensionStoreNodeList
  edges: [ExtensionStoreEdge!]!
  nodes: [ExtensionStoreType!]!
  pageInfo: PageInfo!
  totalCount: Int!

## SettingsTypeInput: (absent)

## SetSettingsInput
  clientMutationId: String
  settings: PartialSettingsTypeInput!

## UserSettingsType: (absent)