package io.lakscastro.sharedstorage.plugin

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Point
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.documentfile.provider.DocumentFile
import com.anggrayudi.storage.file.child
import io.flutter.plugin.common.*
import io.lakscastro.sharedstorage.ROOT_CHANNEL
import io.lakscastro.sharedstorage.SharedStoragePlugin
import io.lakscastro.sharedstorage.common.*
import io.lakscastro.sharedstorage.plugin.lib.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * APIs implementations are contained in this class and used by [SharedStoragePlugin]
 */
class SharedStorageApi(val plugin: SharedStoragePlugin) :
  MethodChannel.MethodCallHandler,
  PluginRegistry.ActivityResultListener,
  Listenable,
  ActivityListener,
  EventChannel.StreamHandler {
  private val pendingResults: MutableMap<Int, Pair<MethodCall, MethodChannel.Result>> =
    mutableMapOf()
  private var channel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var eventSink: EventChannel.EventSink? = null

  companion object {
    private const val CHANNEL = "documentfile"
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      GET_DOCUMENT_THUMBNAIL -> {
        if (Build.VERSION.SDK_INT >= API_21) {
          val uri = Uri.parse(call.argument("uri"))
          val width = call.argument<Int>("width")!!
          val height = call.argument<Int>("height")!!

          val bitmap =
            DocumentsContract.getDocumentThumbnail(
              plugin.context.contentResolver,
              uri,
              Point(width, height),
              null
            )

          CoroutineScope(Dispatchers.Default).launch {
            if (bitmap != null) {
              val base64 = bitmapToBase64(bitmap)

              val data =
                mapOf(
                  "base64" to base64,
                  "uri" to "$uri",
                  "width" to bitmap.width,
                  "height" to bitmap.height,
                  "byteCount" to bitmap.byteCount,
                  "density" to bitmap.density
                )

              launch(Dispatchers.Main) { result.success(data) }
            }
          }
        } else {
          result.notSupported(call.method, API_21)
        }
      }
      GET_DOCUMENT_CONTENT -> {
        val uri = Uri.parse(call.argument<String>("uri")!!)

        if (Build.VERSION.SDK_INT >= API_21) {
          CoroutineScope(Dispatchers.IO).launch {
            val content = readDocumentContent(uri)

            launch(Dispatchers.Main) { result.success(content) }
          }
        } else {
          result.notSupported(call.method, API_21)
        }
      }
      OPEN_DOCUMENT_TREE ->
        if (Build.VERSION.SDK_INT >= API_21) {
          openDocumentTree(call, result)
        }
      CREATE_FILE ->
          if (Build.VERSION.SDK_INT >= API_21) {
            createFile(
                result,
                call.argument<String>("mimeType")!!,
                call.argument<String>("displayName")!!,
                call.argument<String>("directoryUri")!!,
                call.argument<ByteArray>("content")!!
            )
          }
      WRITE_TO_FILE ->
          writeToFile(
              result,
              call.argument<String>("uri")!!,
              call.argument<ByteArray>("content")!!,
              call.argument<String>("mode")!!
          )
      PERSISTED_URI_PERMISSIONS ->
        persistedUriPermissions(result)
      RELEASE_PERSISTABLE_URI_PERMISSION ->
        releasePersistableUriPermission(
          result,
          call.argument<String?>("uri") as String
        )
      FROM_TREE_URI ->
        if (Build.VERSION.SDK_INT >= API_21) {
          result.success(
            createDocumentFileMap(
              documentFromUri(
                plugin.context,
                call.argument<String?>("uri") as String
              )
            )
          )
        }
      CAN_WRITE ->
        if (Build.VERSION.SDK_INT >= API_21) {
          result.success(
            documentFromUri(
              plugin.context,
              call.argument<String?>("uri") as String
            )?.canWrite()
          )
        }
      CAN_READ ->
        if (Build.VERSION.SDK_INT >= API_21) {
          val uri = call.argument<String?>("uri") as String

          result.success(documentFromUri(plugin.context, uri)?.canRead())
        }
      LENGTH ->
        if (Build.VERSION.SDK_INT >= API_21) {
          result.success(
            documentFromUri(
              plugin.context,
              call.argument<String?>("uri") as String
            )?.length()
          )
        }
      EXISTS ->
        if (Build.VERSION.SDK_INT >= API_21) {
          result.success(
            documentFromUri(
              plugin.context,
              call.argument<String?>("uri") as String
            )?.exists()
          )
        }
      DELETE ->
        if (Build.VERSION.SDK_INT >= API_21) {
          result.success(
            documentFromUri(
              plugin.context,
              call.argument<String?>("uri") as String
            )?.delete()
          )
        }
      LAST_MODIFIED ->
        if (Build.VERSION.SDK_INT >= API_21) {
          val document = documentFromUri(
            plugin.context,
            call.argument<String?>("uri") as String
          )

          result.success(document?.lastModified())
        }
      CREATE_DIRECTORY -> {
        if (Build.VERSION.SDK_INT >= API_21) {
          val uri = call.argument<String?>("uri") as String
          val displayName = call.argument<String?>("displayName") as String

          val createdDirectory =
            documentFromUri(plugin.context, uri)?.createDirectory(displayName) ?: return

          result.success(createDocumentFileMap(createdDirectory))
        } else {
          result.notSupported(call.method, API_21)
        }
      }
      FIND_FILE -> {
        if (Build.VERSION.SDK_INT >= API_21) {
          val uri = call.argument<String?>("uri") as String
          val displayName = call.argument<String?>("displayName") as String

          result.success(
            createDocumentFileMap(
              documentFromUri(
                plugin.context,
                uri
              )?.findFile(displayName)
            )
          )
        }
      }
      COPY -> {
        val uri = Uri.parse(call.argument<String>("uri")!!)
        val destination = Uri.parse(call.argument<String>("destination")!!)

        if (Build.VERSION.SDK_INT >= API_21) {
          if (Build.VERSION.SDK_INT >= API_24) {
            DocumentsContract.copyDocument(plugin.context.contentResolver, uri, destination)
          } else {
            val inputStream = openInputStream(uri)
            val outputStream = openOutputStream(destination)

            outputStream?.let { inputStream?.copyTo(it) }
          }
        } else {
          result.notSupported(
            RENAME_TO,
            API_21,
            mapOf("uri" to "$uri", "destination" to "$destination")
          )
        }
      }
      RENAME_TO -> {
        val uri = call.argument<String?>("uri") as String
        val displayName = call.argument<String?>("displayName") as String

        if (Build.VERSION.SDK_INT >= API_21) {
          documentFromUri(plugin.context, uri)?.apply {
            val success = renameTo(displayName)

            result.success(
              if (success) createDocumentFileMap(
                documentFromUri(
                  plugin.context,
                  this.uri
                )!!
              )
              else null
            )
          }
        } else {
          result.notSupported(RENAME_TO, API_21, mapOf("uri" to uri, "displayName" to displayName))
        }
      }
      PARENT_FILE -> {
        val uri = call.argument<String>("uri")!!

        if (Build.VERSION.SDK_INT >= API_21) {
          val parent = documentFromUri(plugin.context, uri)?.parentFile

          result.success(if (parent != null) createDocumentFileMap(parent) else null)
        } else {
          result.notSupported(PARENT_FILE, API_21, mapOf("uri" to uri))
        }
      }
      CHILD -> {
        val uri = call.argument<String>("uri")!!
        val path = call.argument<String>("path")!!
        val requiresWriteAccess = call.argument<Boolean>("requiresWriteAccess") ?: false

        if (Build.VERSION.SDK_INT >= API_21) {
          val document = documentFromUri(plugin.context, uri)
          val childDocument =
            document?.child(plugin.context, path, requiresWriteAccess)

          result.success(createDocumentFileMap(childDocument))
        } else {
          result.notSupported(CHILD, API_21, mapOf("uri" to uri))
        }
      }
      OPEN_DOCUMENT_FILE -> openDocumentFile(call, result)
      else -> result.notImplemented()
    }
  }

  private fun openDocumentFile(call: MethodCall, result: MethodChannel.Result) {
    val uri = Uri.parse(call.argument<String>("uri")!!)
    val type =
      call.argument<String>("type") ?: plugin.context.contentResolver.getType(
        uri
      )

    val intent =
      Intent(Intent.ACTION_VIEW).apply {
        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        data = uri
      }

    try {
      plugin.binding?.activity?.startActivity(intent, null)

      Log.d("sharedstorage", "Successfully launched uri $uri ")

      result.success(null)
    } catch (e: ActivityNotFoundException) {
      result.error(
        EXCEPTION_ACTIVITY_NOT_FOUND,
        "There's no activity handler that can process the uri $uri of type $type",
        mapOf("uri" to "$uri", "type" to type)
      )
    } catch (e: SecurityException) {
      result.error(
        EXCEPTION_CANT_OPEN_FILE_DUE_SECURITY_POLICY,
        "Missing read and write permissions for uri $uri of type $type to launch ACTION_VIEW activity",
        mapOf("uri" to "$uri", "type" to "$type")
      )
    } catch (e: Throwable) {
      result.error(
        EXCEPTION_CANT_OPEN_DOCUMENT_FILE,
        "Couldn't start activity to open document file for uri: $uri",
        mapOf("uri" to "$uri")
      )
    }
  }

  @RequiresApi(API_21)
  private fun openDocumentTree(call: MethodCall, result: MethodChannel.Result) {
    val grantWritePermission = call.argument<Boolean>("grantWritePermission")!!

    val initialUri = call.argument<String>("initialUri")

    val intent =
      Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
        addFlags(
          if (grantWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION
          else Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        if (initialUri != null) {
          val tree = DocumentFile.fromTreeUri(plugin.context, Uri.parse(initialUri))

          if (Build.VERSION.SDK_INT >= API_26) {
            putExtra(
              if (Build.VERSION.SDK_INT >= API_26) DocumentsContract.EXTRA_INITIAL_URI
              else DOCUMENTS_CONTRACT_EXTRA_INITIAL_URI,
              tree?.uri
            )
          }
        }
      }

    if (pendingResults[OPEN_DOCUMENT_TREE_CODE] != null) return

    pendingResults[OPEN_DOCUMENT_TREE_CODE] = Pair(call, result)

    plugin.binding?.activity?.startActivityForResult(intent, OPEN_DOCUMENT_TREE_CODE)
  }

  @RequiresApi(API_21)
  private fun createFile(
    result: MethodChannel.Result,
    mimeType: String,
    displayName: String,
    directory: String,
    content: ByteArray
  ) {
    createFile(Uri.parse(directory), mimeType, displayName, content) {
      result.success(createDocumentFileMap(this))
    }
  }

  @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
  private fun createFile(
    treeUri: Uri,
    mimeType: String,
    displayName: String,
    content: ByteArray,
    block: DocumentFile?.() -> Unit
  ) {
    val createdFile = documentFromUri(plugin.context, treeUri)!!.createFile(mimeType, displayName)

    createdFile?.uri?.apply {
      plugin.context.contentResolver.openOutputStream(this)?.apply {
        write(content)
        flush()

        val createdFileDocument = documentFromUri(plugin.context, createdFile.uri)

        block(createdFileDocument)
      }
    }
  }

  private fun writeToFile(
    result: MethodChannel.Result,
    uri: String,
    content: ByteArray,
    mode: String
  ) {
    try {
      plugin.context.contentResolver.openOutputStream(Uri.parse(uri), mode)?.apply {
        write(content)
        flush()
        close()

        result.success(true)
      }
    } catch (e: Exception) {
      result.success(false)
    }
  }

  @RequiresApi(API_19)
  private fun persistedUriPermissions(result: MethodChannel.Result) {
    val persistedUriPermissions = plugin.context.contentResolver.persistedUriPermissions

    result.success(
      persistedUriPermissions
        .map {
          mapOf(
            "isReadPermission" to it.isReadPermission,
            "isWritePermission" to it.isWritePermission,
            "persistedTime" to it.persistedTime,
            "uri" to "${it.uri}"
          )
        }
        .toList()
    )
  }

  @RequiresApi(API_19)
  private fun releasePersistableUriPermission(result: MethodChannel.Result, directoryUri: String) {
    plugin.context.contentResolver.releasePersistableUriPermission(
      Uri.parse(directoryUri),
      Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    )

    result.success(null)
  }

  @RequiresApi(API_19)
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    when (requestCode) {
      OPEN_DOCUMENT_TREE_CODE -> {
        val pendingResult = pendingResults[OPEN_DOCUMENT_TREE_CODE] ?: return false

        val grantWritePermission = pendingResult.first.argument<Boolean>("grantWritePermission")!!

        try {
          val uri = data?.data

          if (uri != null) {
            plugin.context.contentResolver.takePersistableUriPermission(
              uri,
              if (grantWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION
              else Intent.FLAG_GRANT_READ_URI_PERMISSION
            )

            pendingResult.second.success("$uri")

            return true
          }

          pendingResult.second.success(null)
        } finally {
          pendingResults.remove(OPEN_DOCUMENT_TREE_CODE)
        }
      }
    }

    return false
  }

  override fun startListening(binaryMessenger: BinaryMessenger) {
    if (channel != null) stopListening()

    channel = MethodChannel(binaryMessenger, "$ROOT_CHANNEL/$CHANNEL")
    channel?.setMethodCallHandler(this)

    eventChannel = EventChannel(binaryMessenger, "$ROOT_CHANNEL/event/$CHANNEL")
    eventChannel?.setStreamHandler(this)
  }

  override fun stopListening() {
    if (channel == null) return

    channel?.setMethodCallHandler(null)
    channel = null

    eventChannel?.setStreamHandler(null)
    eventChannel = null
  }

  override fun startListeningToActivity() {
    plugin.binding?.addActivityResultListener(this)
  }

  override fun stopListeningToActivity() {
    plugin.binding?.removeActivityResultListener(this)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    val args = arguments as Map<*, *>

    eventSink = events

    when (args["event"]) {
      LIST_FILES -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        listFilesEvent(eventSink, args)
      }
    }
  }

  /**
   * Read files of a given `uri` and dispatches all files under it through the `eventSink` and
   * closes the stream after the last record
   *
   * Useful to read files under a `uri` with a large set of children
   */
  private fun listFilesEvent(eventSink: EventChannel.EventSink?, args: Map<*, *>) {
    if (eventSink == null) return

    val columns = args["columns"] as List<*>
    val uri = Uri.parse(args["uri"] as String)
    val document = DocumentFile.fromTreeUri(plugin.context, uri)

    if (document == null) {
      eventSink.error(
        EXCEPTION_NOT_SUPPORTED,
        "Android SDK must be greater or equal than [Build.VERSION_CODES.N]",
        "Got (Build.VERSION.SDK_INT): ${Build.VERSION.SDK_INT}"
      )
    } else {
      if (!document.canRead()) {
        val error = "You cannot read a URI that you don't have read permissions"

        Log.d("NO PERMISSION!!!", error)

        eventSink.error(
          EXCEPTION_MISSING_PERMISSIONS,
          error,
          mapOf("uri" to args["uri"])
        )

        eventSink.endOfStream()
      } else {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
          CoroutineScope(Dispatchers.IO).launch {
            try {
              traverseDirectoryEntries(
                plugin.context.contentResolver,
                rootOnly = true,
                targetUri = document.uri,
                columns =
                columns
                  .map { parseDocumentFileColumn(parseDocumentFileColumn(it as String)!!) }
                  .toTypedArray()
              ) { data, _ -> launch(Dispatchers.Main) { eventSink.success(data) } }
            } finally {
              launch(Dispatchers.Main) { eventSink.endOfStream() }
            }
          }
        }
      }
    }
  }

  /** Alias for `plugin.context.contentResolver.openOutputStream(uri)` */
  private fun openOutputStream(uri: Uri): OutputStream? {
    return plugin.context.contentResolver.openOutputStream(uri)
  }

  /** Alias for `plugin.context.contentResolver.openInputStream(uri)` */
  private fun openInputStream(uri: Uri): InputStream? {
    return plugin.context.contentResolver.openInputStream(uri)
  }

  /** Get a document content as `ByteArray` equivalent to `Uint8List` in Dart */
  @RequiresApi(API_21)
  private fun readDocumentContent(uri: Uri): ByteArray? {
    return try {
      val inputStream = openInputStream(uri)

      val bytes = inputStream?.readBytes()

      inputStream?.close()

      bytes
    } catch (e: FileNotFoundException) {
      null
    } catch (e: IOException) {
      null
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}
