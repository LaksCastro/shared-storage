import 'package:flutter/services.dart';

const String kRootChannel = 'io.alexrintt.plugins/sharedstorage';

/// `MethodChannels` of this plugin. Flutter use this to communicate with native Android

/// Target [Environment] Android API (Legacy and you should avoid it)
const MethodChannel kEnvironmentChannel =
    MethodChannel('$kRootChannel/environment');

/// Target [MediaStore] Android API
const MethodChannel kMediaStoreChannel =
    MethodChannel('$kRootChannel/mediastore');

/// Target [DocumentFile] from `SAF` Android API (New Android APIs use it)
const MethodChannel kDocumentFileChannel =
    MethodChannel('$kRootChannel/documentfile');

/// Target [DocumentsContract] from `SAF` Android API (New Android APIs use it)
const MethodChannel kDocumentsContractChannel =
    MethodChannel('$kRootChannel/documentscontract');

/// Target [DocumentFileHelper] Shared Storage plugin class (SAF Based)
const MethodChannel kDocumentFileHelperChannel =
    MethodChannel('$kRootChannel/documentfilehelper');

/// `EventChannels` of this plugin. Flutter use this to communicate with native Android

/// Target [DocumentFile] from `SAF` Android API (New Android APIs use it)
const EventChannel kDocumentFileEventChannel =
    EventChannel('$kRootChannel/event/documentfile');
