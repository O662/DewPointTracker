package com.weatherdew.app.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * Native port of the app's weather icon painter
 * (lib/widgets/weather_glyph.dart) so the widgets show the exact same glyphs
 * as the app. Geometry is expressed as fractions of the bitmap size, matching
 * the Dart painter; blur radii scale from the painter's reference 120px size.
 */
object GlyphRenderer {
    private const val SUN_A = 0xFFFFE08A.toInt()
    private const val SUN_B = 0xFFFFB24D.toInt()
    private const val MOON = 0xFFE9F1FF.toInt()
    private const val CLOUD = 0xFFF3F7FC.toInt()
    private const val CLOUD_DIM = 0xFFD8E0EA.toInt()
    private const val DROP = 0xFF9FD4F5.toInt()
    private const val BOLT = 0xFFFFD45A.toInt()

    fun bitmap(context: Context, code: Int, isDay: Boolean, sizeDp: Int): Bitmap {
        val px = (sizeDp * context.resources.displayMetrics.density).toInt()
            .coerceAtLeast(16)
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val s = px.toFloat()
        when (Conditions.category(code)) {
            SkyCategory.CLEAR ->
                if (isDay) sun(c, s, 0.5f, 0.46f, 1f) else moon(c, s, 0.5f, 0.46f, 1f)
            SkyCategory.PARTLY -> {
                if (isDay) sun(c, s, 0.66f, 0.34f, 0.7f) else moon(c, s, 0.66f, 0.34f, 0.7f)
                cloud(c, s, 0f, 0.06f, 1f, CLOUD)
            }
            SkyCategory.CLOUDY -> {
                cloud(c, s, 0f, 0f, 1f, CLOUD_DIM)
                cloud(c, s, -0.12f, -0.1f, 0.7f, CLOUD)
            }
            SkyCategory.FOG -> {
                cloud(c, s, 0f, -0.08f, 1f, CLOUD)
                fogLines(c, s)
            }
            SkyCategory.DRIZZLE -> {
                cloud(c, s, 0f, -0.08f, 1f, CLOUD)
                drops(c, s, 2)
            }
            SkyCategory.RAIN -> {
                cloud(c, s, 0f, -0.08f, 1f, CLOUD)
                drops(c, s, 3)
            }
            SkyCategory.SNOW -> {
                cloud(c, s, 0f, -0.08f, 1f, CLOUD)
                flakes(c, s)
            }
            SkyCategory.THUNDER -> {
                cloud(c, s, 0f, -0.08f, 1f, CLOUD_DIM)
                bolt(c, s)
            }
        }
        return bmp
    }

    // The Dart painter's blur radii are tuned for a ~120px glyph.
    private fun blur(s: Float, radius: Float) = max(1f, radius * s / 120f)

    private fun alpha(color: Int, a: Float): Int =
        (color and 0x00FFFFFF) or ((a * 255).toInt() shl 24)

    private fun paint() = Paint(Paint.ANTI_ALIAS_FLAG)

    private fun sun(c: Canvas, s: Float, fx: Float, fy: Float, scale: Float) {
        val cx = s * fx
        val cy = s * fy
        val r = s * 0.17f * scale

        c.drawCircle(cx, cy, r * 1.5f, paint().apply {
            color = alpha(SUN_B, 0.35f)
            maskFilter = BlurMaskFilter(blur(s, 18f), BlurMaskFilter.Blur.NORMAL)
        })

        val rays = paint().apply {
            color = SUN_A
            strokeWidth = s * 0.035f * scale
            strokeCap = Paint.Cap.ROUND
        }
        for (i in 0 until 8) {
            val a = i * Math.PI.toFloat() / 4
            val dx = cos(a)
            val dy = sin(a)
            c.drawLine(
                cx + dx * r * 1.5f, cy + dy * r * 1.5f,
                cx + dx * r * 2.1f, cy + dy * r * 2.1f, rays,
            )
        }

        c.drawCircle(cx, cy, r, paint().apply {
            shader = RadialGradient(
                cx, cy, r, SUN_A, SUN_B, Shader.TileMode.CLAMP)
        })
    }

    private fun moon(c: Canvas, s: Float, fx: Float, fy: Float, scale: Float) {
        val cx = s * fx
        val cy = s * fy
        val r = s * 0.18f * scale

        c.drawCircle(cx, cy, r * 1.3f, paint().apply {
            color = alpha(MOON, 0.30f)
            maskFilter = BlurMaskFilter(blur(s, 16f), BlurMaskFilter.Blur.NORMAL)
        })

        // Crescent: full disc minus an offset disc.
        val disc = Path().apply {
            addOval(RectF(cx - r, cy - r, cx + r, cy + r), Path.Direction.CW)
        }
        val cutCx = cx + r * 0.55f
        val cutCy = cy - r * 0.35f
        val cut = Path().apply {
            addOval(RectF(cutCx - r, cutCy - r, cutCx + r, cutCy + r), Path.Direction.CW)
        }
        val crescent = Path()
        crescent.op(disc, cut, Path.Op.DIFFERENCE)
        c.drawPath(crescent, paint().apply { color = MOON })
    }

    private fun cloud(
        c: Canvas, s: Float, xOffset: Float, yOffset: Float, scale: Float, color: Int,
    ) {
        val dx = s * xOffset
        val dy = s * yOffset
        val path = Path().apply {
            addRoundRect(
                RectF(s * 0.20f + dx, s * 0.58f + dy, s * 0.80f + dx, s * 0.80f + dy),
                s * 0.13f * scale, s * 0.13f * scale, Path.Direction.CW,
            )
            addCircle(s * 0.34f + dx, s * 0.58f + dy, s * 0.15f * scale, Path.Direction.CW)
            addCircle(s * 0.52f + dx, s * 0.47f + dy, s * 0.21f * scale, Path.Direction.CW)
            addCircle(s * 0.66f + dx, s * 0.56f + dy, s * 0.16f * scale, Path.Direction.CW)
        }

        val shadow = Path(path)
        shadow.offset(0f, 6f * s / 120f)
        c.drawPath(shadow, paint().apply {
            // this.: the cloud() parameter named "color" shadows Paint.color.
            this.color = alpha(Color.BLACK, 0.12f)
            maskFilter = BlurMaskFilter(blur(s, 12f), BlurMaskFilter.Blur.NORMAL)
        })
        c.drawPath(path, paint().apply { this.color = color })
    }

    private fun drops(c: Canvas, s: Float, count: Int) {
        val p = paint().apply {
            color = DROP
            strokeWidth = s * 0.04f
            strokeCap = Paint.Cap.ROUND
        }
        val xs = when (count) {
            3 -> floatArrayOf(0.38f, 0.52f, 0.66f)
            2 -> floatArrayOf(0.44f, 0.6f)
            else -> floatArrayOf(0.52f)
        }
        for (fx in xs) {
            c.drawLine(s * fx, s * 0.80f, s * (fx - 0.04f), s * 0.92f, p)
        }
    }

    private fun flakes(c: Canvas, s: Float) {
        val p = paint().apply { color = CLOUD }
        c.drawCircle(s * 0.40f, s * 0.86f, s * 0.028f, p)
        c.drawCircle(s * 0.54f, s * 0.92f, s * 0.028f, p)
        c.drawCircle(s * 0.66f, s * 0.85f, s * 0.028f, p)
    }

    private fun fogLines(c: Canvas, s: Float) {
        val p = paint().apply {
            color = alpha(CLOUD, 0.85f)
            strokeWidth = s * 0.045f
            strokeCap = Paint.Cap.ROUND
        }
        for (i in 0 until 3) {
            val y = s * (0.82f + i * 0.06f)
            val inset = s * (0.26f + i * 0.03f)
            c.drawLine(inset, y, s - inset, y, p)
        }
    }

    private fun bolt(c: Canvas, s: Float) {
        val path = Path().apply {
            moveTo(s * 0.54f, s * 0.78f)
            lineTo(s * 0.44f, s * 0.90f)
            lineTo(s * 0.52f, s * 0.90f)
            lineTo(s * 0.46f, s * 1.0f)
            lineTo(s * 0.62f, s * 0.86f)
            lineTo(s * 0.53f, s * 0.86f)
            close()
        }
        c.drawPath(path, paint().apply {
            color = alpha(BOLT, 0.5f)
            maskFilter = BlurMaskFilter(blur(s, 8f), BlurMaskFilter.Blur.NORMAL)
        })
        c.drawPath(path, paint().apply { color = BOLT })
    }
}
