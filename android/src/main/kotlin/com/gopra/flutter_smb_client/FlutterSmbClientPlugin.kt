// In android/src/main/kotlin/com/gopra/flutter_smb_client/FlutterSmbClientPlugin.kt
package com.gopra.flutter_smb_client

import androidx.annotation.NonNull
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class FlutterSmbClientPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var client: SMBClient? = null
  private var connection: Connection? = null
  private var session: Session? = null
  private var share: DiskShare? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_smb_client")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "connect" -> {
        try {
          val host = call.argument<String>("host")!!
          val username = call.argument<String>("username")!!
          val password = call.argument<String>("password")!!
          val domain = call.argument<String>("domain") ?: ""
          val port = call.argument<Int>("port") ?: 445

          client = SMBClient()
          connection = client?.connect(host)
          val ac = AuthenticationContext(username, password.toCharArray(), domain)
          session = connection?.authenticate(ac)
          share = session?.connectShare("shared") as DiskShare?

          result.success(true)
        } catch (e: Exception) {
          result.error("CONNECTION_ERROR", e.message, null)
        }
      }

      "listFiles" -> {
        try {
          val path = call.argument<String>("path")!!
          val files = share?.list(path)
          val fileList = files?.map {
            mapOf(
              "name" to it.fileName,
              "size" to it.fileAttributes.size,
              "isDirectory" to it.fileAttributes.isDirectory
            )
          }
          result.success(fileList)
        } catch (e: Exception) {
          result.error("LIST_ERROR", e.message, null)
        }
      }

      "downloadFile" -> {
        try {
          val remotePath = call.argument<String>("remotePath")!!
          val localPath = call.argument<String>("localPath")!!
          
          val file = share?.openFile(remotePath, setOf())
          val outputStream = FileOutputStream(File(localPath))
          file?.inputStream?.copyTo(outputStream)
          
          outputStream.close()
          file?.close()
          
          result.success(localPath)
        } catch (e: Exception) {
          result.error("DOWNLOAD_ERROR", e.message, null)
        }
      }

      "uploadFile" -> {
        try {
          val localPath = call.argument<String>("localPath")!!
          val remotePath = call.argument<String>("remotePath")!!
          
          val inputStream = FileInputStream(File(localPath))
          val file = share?.openFile(remotePath, setOf())
          
          inputStream.copyTo(file?.outputStream!!)
          
          inputStream.close()
          file.close()
          
          result.success(true)
        } catch (e: Exception) {
          result.error("UPLOAD_ERROR", e.message, null)
        }
      }

      "disconnect" -> {
        try {
          share?.close()
          session?.close()
          connection?.close()
          client?.close()
          
          result.success(true)
        } catch (e: Exception) {
          result.error("DISCONNECT_ERROR", e.message, null)
        }
      }

      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}