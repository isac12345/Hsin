package com.hsin

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream

/**
 * Gambar dari galeri DISALIN ke penyimpanan app (diperkecil + dirotasi sesuai EXIF),
 * jadi tidak bergantung izin URI dan tidak memuat bitmap raksasa di UI thread.
 */
object Images {
    const val BANNER = "banner.jpg"
    const val WALL = "wall.jpg"

    fun file(ctx: Context, name: String) = File(ctx.filesDir, name)

    private fun sample(w: Int, h: Int, maxSide: Int): Int {
        var s = 1
        while (w / (s * 2) >= maxSide || h / (s * 2) >= maxSide) s *= 2
        return s
    }

    fun saveFrom(ctx: Context, uri: Uri, name: String, maxSide: Int): Boolean {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sample(bounds.outWidth, bounds.outHeight, maxSide)
            }
            var bmp = ctx.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
                ?: return false
            val orientation = ctx.contentResolver.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL
            val m = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            }
            if (!m.isIdentity) {
                val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                if (rotated !== bmp) bmp.recycle()
                bmp = rotated
            }
            val tmp = File(ctx.filesDir, "$name.tmp")
            FileOutputStream(tmp).use { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }
            bmp.recycle()
            val dest = file(ctx, name)
            if (dest.exists()) dest.delete()
            tmp.renameTo(dest)
        } catch (e: Exception) {
            false
        } catch (e: OutOfMemoryError) {
            false
        }
    }

    fun load(ctx: Context, name: String, maxSide: Int): ImageBitmap? {
        val f = file(ctx, name)
        if (!f.exists()) return null
        return try {
            val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(f.absolutePath, b)
            val o = BitmapFactory.Options().apply { inSampleSize = sample(b.outWidth, b.outHeight, maxSide) }
            BitmapFactory.decodeFile(f.absolutePath, o)?.asImageBitmap()
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    fun loadDefaultBanner(ctx: Context): ImageBitmap? {
        return try {
            val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeResource(ctx.resources, R.drawable.banner_default, b)
            val o = BitmapFactory.Options().apply { inSampleSize = sample(b.outWidth, b.outHeight, 1400) }
            BitmapFactory.decodeResource(ctx.resources, R.drawable.banner_default, o)?.asImageBitmap()
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    fun loadDefaultWall(ctx: Context): ImageBitmap? {
        return try {
            val b = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeResource(ctx.resources, R.drawable.wallpaper_default, b)
            val o = BitmapFactory.Options().apply { inSampleSize = sample(b.outWidth, b.outHeight, 1600) }
            BitmapFactory.decodeResource(ctx.resources, R.drawable.wallpaper_default, o)?.asImageBitmap()
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    fun delete(ctx: Context, name: String) {
        file(ctx, name).delete()
    }
}
