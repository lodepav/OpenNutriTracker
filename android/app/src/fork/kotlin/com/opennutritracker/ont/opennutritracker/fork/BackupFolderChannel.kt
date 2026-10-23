package com.opennutritracker.ont.opennutritracker.fork

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The automatic backup's folder (fork phase 2): one picked with the system's folder picker
 * (Storage Access Framework), kept with a persisted grant, so the app can list, write, read and
 * delete its backups there after a restart or an update. Registered by seam S22 in MainActivity.
 *
 * Every call but `pick` takes the folder's `uri`. Errors are `access_denied` (the grant is
 * gone, e.g. after a reinstall) or `io`.
 */
class BackupFolderChannel(private val activity: ComponentActivity, engine: FlutterEngine) {
    private val scope = CoroutineScope(Dispatchers.Main)
    private var pending: MethodChannel.Result? = null

    private val picker = activity.activityResultRegistry.register(
        "fork_backup_folder", ActivityResultContracts.OpenDocumentTree()
    ) { uri -> picked(uri) }

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "openbite/backup_folder")
            .setMethodCallHandler { call, result ->
                if (call.method == "pick") {
                    pending?.success(null)
                    pending = result
                    picker.launch(null)
                    return@setMethodCallHandler
                }
                val tree = Uri.parse(call.argument<String>("uri"))
                val name = call.argument<String>("name")
                scope.launch {
                    try {
                        val value = withContext(Dispatchers.IO) {
                            if (!granted(tree)) throw SecurityException()
                            when (call.method) {
                                "list" -> children(tree).keys.toList()
                                "write" -> write(tree, name!!, call.argument<ByteArray>("bytes")!!)
                                "read" -> children(tree)[name]?.let { read(it) }
                                "delete" -> children(tree)[name]?.let {
                                    DocumentsContract.deleteDocument(activity.contentResolver, it)
                                }
                                else -> Unit
                            }
                        }
                        if (call.method in listOf("list", "write", "read", "delete")) {
                            result.success(if (value == Unit || value is Boolean) null else value)
                        } else {
                            result.notImplemented()
                        }
                    } catch (e: SecurityException) {
                        result.error("access_denied", null, null)
                    } catch (e: Exception) {
                        result.error("io", e.javaClass.simpleName, null)
                    }
                }
            }
    }

    private fun picked(uri: Uri?) {
        val result = pending ?: return
        pending = null
        if (uri == null) return result.success(null)
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
        } catch (e: Exception) {
            result.error("access_denied", null, null)
        }
    }

    private fun granted(tree: Uri) = activity.contentResolver.persistedUriPermissions
        .any { it.uri == tree && it.isReadPermission && it.isWritePermission }

    private fun folder(tree: Uri) =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun displayName(tree: Uri): String =
        activity.contentResolver.query(
            folder(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null
        )?.use { if (it.moveToFirst()) it.getString(0) else null } ?: tree.lastPathSegment ?: ""

    /** The folder's files by name. */
    private fun children(tree: Uri): Map<String, Uri> {
        val list = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        val found = mutableMapOf<String, Uri>()
        activity.contentResolver.query(list, columns, null, null, null)?.use {
            while (it.moveToNext()) {
                found[it.getString(1)] = DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0))
            }
        }
        return found
    }

    /** Writes [name], replacing a file of that name. */
    private fun write(tree: Uri, name: String, bytes: ByteArray) {
        val file = children(tree)[name]
            ?: DocumentsContract.createDocument(activity.contentResolver, folder(tree), "application/zip", name)
            ?: throw java.io.IOException("create failed")
        activity.contentResolver.openOutputStream(file, "wt")?.use { it.write(bytes) }
            ?: throw java.io.IOException("open failed")
    }

    private fun read(file: Uri): ByteArray =
        activity.contentResolver.openInputStream(file)?.use { it.readBytes() }
            ?: throw java.io.IOException("open failed")
}
