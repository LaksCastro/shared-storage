import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_storage/shared_storage.dart';

import '../../theme/spacing.dart';
import '../../widgets/buttons.dart';
import '../../widgets/key_value_text.dart';
import '../../widgets/simple_card.dart';
import 'file_explorer_page.dart';

class FileExplorerCard extends StatefulWidget {
  const FileExplorerCard({
    Key? key,
    required this.partialFile,
    required this.didUpdateDocument,
  }) : super(key: key);

  final PartialDocumentFile partialFile;
  final void Function(PartialDocumentFile?) didUpdateDocument;

  @override
  _FileExplorerCardState createState() => _FileExplorerCardState();
}

class _FileExplorerCardState extends State<FileExplorerCard> {
  PartialDocumentFile get file => widget.partialFile;

  static const _size = Size.square(150);

  Uint8List? imageBytes;

  Future<void> _loadThumbnailIfAvailable() async {
    final uri = file.metadata?.uri;

    if (uri == null) return;

    final bitmap = await getDocumentThumbnail(
      uri: uri,
      width: _size.width,
      height: _size.height,
    );

    if (bitmap == null || !mounted) return;

    setState(() => imageBytes = bitmap.bytes);
  }

  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();

    _loadThumbnailIfAvailable();
  }

  @override
  void didUpdateWidget(covariant FileExplorerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.partialFile.data?[DocumentFileColumn.id] !=
        widget.partialFile.data?[DocumentFileColumn.id]) {
      _loadThumbnailIfAvailable();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _openFolderFileListPage(Uri uri) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileExplorerPage(uri: uri),
      ),
    );
  }

  Uint8List? content;

  bool get _isDirectory => file.metadata?.isDirectory ?? false;

  int _generateLuckNumber() {
    final random = Random();

    return random.nextInt(1000);
  }

  @override
  Widget build(BuildContext context) {
    return SimpleCard(
      onTap: () async {
        if (file.metadata?.isDirectory == false) {
          content = await getDocumentContent(file.metadata!.uri!);

          final mimeType =
              file.data![DocumentFileColumn.mimeType] as String? ?? '';

          if (content != null) {
            final isImage = mimeType.startsWith('image/');

            await showModalBottomSheet(
              context: context,
              builder: (context) {
                if (isImage) {
                  return Image.memory(content!);
                }

                final contentAsString = String.fromCharCodes(content!);

                final fileIsEmpty = contentAsString.isEmpty;

                return Container(
                  padding: k8dp.all,
                  child: Text(
                    fileIsEmpty ? 'This file is empty' : contentAsString,
                    style: TextStyle(
                      color: fileIsEmpty ? Colors.black26 : null,
                      fontStyle: fileIsEmpty ? FontStyle.italic : null,
                    ),
                  ),
                );
              },
            );
          }
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: imageBytes == null
              ? Container(
                  height: _size.height,
                  width: _size.width,
                  color: Colors.grey,
                )
              : Image.memory(
                  imageBytes!,
                  height: _size.height,
                  width: _size.width,
                  fit: BoxFit.contain,
                ),
        ),
        KeyValueText(
          entries: {
            'name': '${file.data?[DocumentFileColumn.displayName]}',
            'type': '${file.data?[DocumentFileColumn.mimeType]}',
            'size': '${file.data?[DocumentFileColumn.size]}',
            'lastModified': '${(() {
              if (file.data?[DocumentFileColumn.lastModified] == null) {
                return null;
              }

              final millisecondsSinceEpoch =
                  file.data?[DocumentFileColumn.lastModified] as int;

              final date =
                  DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);

              return date.toIso8601String();
            })()}',
            'summary': '${file.data?[DocumentFileColumn.summary]}',
            'id': '${file.data?[DocumentFileColumn.id]}',
            'parentUri': '${file.metadata?.parentUri}',
            'uri': '${file.metadata?.uri}',
          },
        ),
        Wrap(
          children: [
            if (_isDirectory)
              ActionButton(
                'Open Directory',
                onTap: () async {
                  if (_isDirectory) {
                    _openFolderFileListPage(
                      file.metadata!.uri!,
                    );
                  }
                },
              ),
            ActionButton(
              'Open With',
              onTap: () async {
                final uri = widget.partialFile.metadata!.uri!;

                try {
                  final launched = await openDocumentFile(uri);

                  if (launched ?? false) {
                    print('Successfully opened $uri');
                  } else {
                    print('Failed to launch $uri');
                  }
                } on PlatformException {
                  print(
                    "There's no activity associated with the file type of this Uri: $uri",
                  );
                }
              },
            ),
            DangerButton(
              'Delete ${_isDirectory ? 'Directory' : 'File'}',
              onTap: () async {
                final deleted = await delete(widget.partialFile.metadata!.uri!);

                if (deleted ?? false) {
                  widget.didUpdateDocument(null);
                }
              },
            ),
            if (!_isDirectory) ...[
              DangerButton(
                'Write to File',
                onTap: () async {
                  await writeToFile(
                    widget.partialFile.metadata!.uri!,
                    content:
                        'Hello World! Your luck number is: ${_generateLuckNumber()}',
                    mode: FileMode.write,
                  );
                },
              ),
              DangerButton(
                'Append to file',
                onTap: () async {
                  final contents = await getDocumentContentAsString(
                    widget.partialFile.metadata!.uri!,
                  );

                  final prependWithNewLine = contents?.isNotEmpty ?? true;

                  await writeToFile(
                    widget.partialFile.metadata!.uri!,
                    content:
                        "${prependWithNewLine ? '\n' : ''}You file got bigger! Here's your luck number: ${_generateLuckNumber()}",
                    mode: FileMode.append,
                  );
                },
              ),
              DangerButton(
                'Erase file content',
                onTap: () async {
                  await writeToFile(
                    widget.partialFile.metadata!.uri!,
                    content: '',
                    mode: FileMode.write,
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}
