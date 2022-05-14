## Stability

The latest version is a Beta release, which means all these APIs can change over a short period of time without prior notice

So, please be aware that this is plugin is not intended for production usage yet, since the API is currently in development.

## Installation

```
flutter pub add shared_storage
```

or

```
dependencies:
  shared_storage: ^latest # Pickup the latest version either from the pub.dev page or the badge in this README.md
```

## Plugin

This plugin include **partial** support for the following APIs:

### Partial Support for [Environment API](/Environment/Usage)

Mirror API from [Environment API](https://developer.android.com/reference/android/os/Environment)

```dart
import 'package:shared_storage/environment.dart' as environment;
```

### Partial Support for [Media Store API](/Media Store/Usage)

Mirror API from [MediaStore provider](https://developer.android.com/reference/android/provider/MediaStore)

```dart
import 'package:shared_storage/media_store.dart' as mediastore;
```

### Partial Support for [Storage Access Framework](/Storage Access Framework/Usage)

Mirror API from [Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)

```dart
import 'package:shared_storage/saf.dart' as saf;
```

All these APIs are module based, which means they are implemented separadely and so you need to import those you want use.

> To request support for some API that is not currently included open a issue explaining your usecase and the API you want to make available, the same applies for new methods or activities for the current APIs.

## Support

If you have ideas to share, bugs to report or need support, you can either open an issue or join our [Discord server](https://discord.gg/86GDERXZNS)

## Android APIs

Most Flutter plugins use Android API's under the hood. So this plugin does the same, and to call native Android storage APIs the following API's are being used:

[`🔗android.os.Environment`](https://developer.android.com/reference/android/os/Environment#summary) [`🔗android.provider.MediaStore`](https://developer.android.com/reference/android/provider/MediaStore#summary) [`🔗android.provider.DocumentsProvider`](https://developer.android.com/guide/topics/providers/document-provider)

## Contributors

These are the brilliant minds behind the development of this plugin!

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tr>
    <td align="center"><a href="https://lakscastro.github.io"><img src="https://avatars.githubusercontent.com/u/51419598?v=4?s=100" width="100px;" alt=""/><br /><sub><b>lask</b></sub></a><br /><a href="https://github.com/lakscastro/shared-storage/commits?author=lakscastro" title="Code">💻</a> <a href="https://github.com/lakscastro/shared-storage/commits?author=lakscastro" title="Documentation">📖</a> <a href="#maintenance-lakscastro" title="Maintenance">🚧</a> <a href="https://github.com/lakscastro/shared-storage/pulls?q=is%3Apr+reviewed-by%3Alakscastro" title="Reviewed Pull Requests">👀</a></td>
  </tr>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
