package com.eyedeadevelopment.fluttertts

import android.content.ContentValues
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.lang.reflect.Field
import java.util.Locale
import java.util.MissingResourceException
import java.util.UUID


/** FlutterTtsPlugin  */
class FlutterTtsPlugin : MethodCallHandler, FlutterPlugin {
    private var handler: Handler? = null
    // nightreader.5：朗讀引擎的每個呼叫都是跨程序呼叫（音色清單一次就是一大包），
    // 不在 Android 主執行緒（也是 Flutter 畫畫面的執行緒）上做，全部照順序交給
    // 這條執行緒；回給 Dart 的結果與事件再送回主執行緒。下面的狀態只在這條執行緒
    // 上讀寫：系統朗讀服務的回呼（onInit、念的進度）也先排到這條執行緒再處理。
    private var workerThread: HandlerThread? = null
    @Volatile private var worker: Handler? = null
    @Volatile private var methodChannel: MethodChannel? = null
    private var speakResult: Result? = null
    private var synthResult: Result? = null
    private var awaitSpeakCompletion = false
    private var speaking = false
    private var awaitSynthCompletion = false
    private var synth = false
    private var context: Context? = null
    private var tts: TextToSpeech? = null
    private val tag = "TTS"
    private val pendingMethodCalls = ArrayList<Runnable>()
    private val utterances = HashMap<String, String>()
    private var bundle: Bundle? = null
    private var silencems = 0
    private var lastProgress = 0
    private var currentText: String? = null
    // nightreader.6：現在念的那一句的 utterance id。換句之後上一句晚到的完成、
    // 錯誤與停止不算，也不放焦點。
    @Volatile private var currentUtteranceId: String? = null
    private var pauseText: String? = null
    private var isPaused: Boolean = false
    private var queueMode: Int = TextToSpeech.QUEUE_FLUSH
    private var ttsStatus: Int? = null
    private var selectedEngine: String? = null
    // 目前這個引擎連的是哪個（建立時指定的，或當時的系統預設）。
    private var connectedEngine: String? = null
    // 正在連的引擎連上時要回覆的那次 setEngine。
    private var engineReply: Result? = null
    private var parcelFileDescriptor: ParcelFileDescriptor? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    companion object {
        private const val SILENCE_PREFIX = "SIL_"
        private const val SYNTHESIZE_TO_FILE_PREFIX = "STF_"
    }

    private fun initInstance(messenger: BinaryMessenger, context: Context) {
        this.context = context
        methodChannel = MethodChannel(messenger, "flutter_tts")
        methodChannel!!.setMethodCallHandler(this)
        handler = Handler(Looper.getMainLooper())
        bundle = Bundle()
        val thread = HandlerThread("flutter_tts").apply { start() }
        workerThread = thread
        worker = Handler(thread.looper)
        // 建立引擎也要查已安裝的朗讀引擎，一起放在這條執行緒。
        onWorker { createEngine(null, null) }
    }

    /** Android Plugin APIs  */
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        initInstance(binding.binaryMessenger, binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        val thread = workerThread
        val lastWorker = worker
        // 之後到的系統回呼都排不進來（[onWorker] 看到 null 就丟掉）。
        worker = null
        workerThread = null
        lastWorker?.post {
            guarded("detach") {
                engineGeneration++
                pendingMethodCalls.clear()
                engineReply = null
                tts?.let {
                    stop()
                    it.shutdown()
                }
                tts = null
                currentUtteranceId = null
                releaseAudioFocus()
                context = null
            }
        }
        // 先做完上面排進去的關閉，再結束這條執行緒。
        thread?.quitSafely()
    }

    /** 排到 [worker] 上做；已經結束（detach）就丟掉。 */
    private fun onWorker(task: () -> Unit) {
        worker?.post { guarded("worker") { task() } }
    }

    /**
     * 在 [worker] 上做的事丟出的例外不會被 Flutter 接住（原本在主執行緒上由
     * MethodChannel 轉成錯誤回覆），不接住會讓整個 App 結束。
     */
    private inline fun guarded(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.e(tag, "$what: $e")
        }
    }

    /**
     * 每個引擎一個：系統朗讀服務在自己的執行緒回呼，排到 [worker] 再處理；換掉的
     * 引擎遲到的回呼不處理，免得改到新引擎正在念的那句。
     */
    private fun progressListener(generation: Int): UtteranceProgressListener {
        val events = utteranceEvents
        return object : UtteranceProgressListener() {
            private fun current(task: () -> Unit) {
                onWorker { if (generation == engineGeneration) task() }
            }

            override fun onStart(utteranceId: String) = current { events.onStart(utteranceId) }

            override fun onDone(utteranceId: String) = current { events.onDone(utteranceId) }

            override fun onStop(utteranceId: String, interrupted: Boolean) =
                current { events.onStop(utteranceId, interrupted) }

            override fun onRangeStart(utteranceId: String, startAt: Int, endAt: Int, frame: Int) =
                current { events.onRangeStart(utteranceId, startAt, endAt, frame) }

            @Deprecated("")
            override fun onError(utteranceId: String) = current { events.onError(utteranceId) }

            override fun onError(utteranceId: String, errorCode: Int) =
                current { events.onError(utteranceId, errorCode) }
        }
    }

    /** 念的進度，在 [worker] 上處理（[progressListener] 排過來的）。 */
    private val utteranceEvents: UtteranceProgressListener =
        object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {
                if (utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
                    invokeMethod("synth.onStart", true)
                } else {
                    if (isPaused) {
                        invokeMethod("speak.onContinue", true)
                        isPaused = false
                    } else {
                        Log.d(tag, "Utterance ID has started: $utteranceId")
                        invokeMethod("speak.onStart", true)
                    }
                }
                if (Build.VERSION.SDK_INT < 26) {
                    // 靜音與存成檔案的那幾句不在 [utterances] 裡。
                    utterances[utteranceId]?.let { onProgress(utteranceId, 0, it.length) }
                }
            }

            override fun onDone(utteranceId: String) {
                if (utteranceId.startsWith(SILENCE_PREFIX)) return
                if (utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
                    closeParcelFileDescriptor(false)
                    Log.d(tag, "Utterance ID has completed: $utteranceId")
                    if (awaitSynthCompletion) {
                        synthCompletion(1)
                    }
                    invokeMethod("synth.onComplete", true)
                } else {
                    // nightreader.6：只認現在念的那一句。換句後上一句晚到的
                    // 完成不回報、不重設進度，也不放掉焦點。
                    if (utteranceId != currentUtteranceId) return
                    currentUtteranceId = null
                    Log.d(tag, "Utterance ID has completed: $utteranceId")
                    if (awaitSpeakCompletion && queueMode == TextToSpeech.QUEUE_FLUSH) {
                        speakCompletion(1)
                    }
                    invokeMethod("speak.onComplete", true)
                }
                lastProgress = 0
                pauseText = null
                utterances.remove(utteranceId)
                releaseAudioFocus()
            }

            override fun onStop(utteranceId: String, interrupted: Boolean) {
                // nightreader.6：舊句晚到的停止不當成現在這一句停了，也不放
                // 掉新的一句的焦點。
                if (utteranceId != currentUtteranceId) return
                currentUtteranceId = null
                Log.d(
                    tag,
                    "Utterance ID has been stopped: $utteranceId. Interrupted: $interrupted"
                )
                if (awaitSpeakCompletion) {
                    speaking = false
                }
                if (isPaused) {
                    invokeMethod("speak.onPause", true)
                } else {
                    invokeMethod("speak.onCancel", true)
                }
                releaseAudioFocus()
            }

            private fun onProgress(utteranceId: String?, startAt: Int, endAt: Int) {
                if (utteranceId != null && !utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
                    val text = utterances[utteranceId] ?: return
                    val data = HashMap<String, String?>()
                    data["text"] = text
                    data["start"] = startAt.toString()
                    data["end"] = endAt.toString()
                    data["word"] = text.substring(startAt, endAt)
                    invokeMethod("speak.onProgress", data)
                }
            }

            // Requires Android 26 or later
            override fun onRangeStart(utteranceId: String, startAt: Int, endAt: Int, frame: Int) {
                if (!utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
                    lastProgress = startAt
                    super.onRangeStart(utteranceId, startAt, endAt, frame)
                    onProgress(utteranceId, startAt, endAt)
                }
            }

            @Deprecated("")
            override fun onError(utteranceId: String) {
                onError(utteranceId, "")
            }

            override fun onError(utteranceId: String, errorCode: Int) {
                onError(utteranceId, " - $errorCode")
            }

            // 等念完（或存完檔）的那次呼叫也要回覆，不然 Dart 那邊一直等。
            private fun onError(utteranceId: String, code: String) {
                if (utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
                    closeParcelFileDescriptor(true)
                    if (awaitSynthCompletion) {
                        synthCompletion(0)
                    }
                    invokeMethod("synth.onError", "Error from TextToSpeech (synth)$code")
                    return
                }
                // nightreader.6：只認現在念的那一句；換句後上一句晚到的錯誤
                // 不回報、不放焦點。
                if (utteranceId != currentUtteranceId) return
                currentUtteranceId = null
                if (awaitSpeakCompletion) {
                    speakCompletion(0)
                }
                invokeMethod("speak.onError", "Error from TextToSpeech (speak)$code")
                releaseAudioFocus()
            }
        }

    /** 在 [worker] 上執行。 */
    fun speakCompletion(success: Int) {
        speaking = false
        speakResult?.success(success)
        speakResult = null
    }

    /** 在 [worker] 上執行。 */
    fun synthCompletion(success: Int) {
        synth = false
        synthResult?.success(success)
        synthResult = null
    }

    // 只認最後建立的那個引擎：換掉的引擎遲到的回呼不能把新引擎當成已經連上，
    // 也不能改到新引擎正在念的那句。只在 [worker] 上讀寫。
    private var engineGeneration = 0

    /**
     * 在 [worker] 上：換成新的引擎（[engine] 為 null 是系統預設）。[reply] 是要
     * 等它連上才回覆的那次 setEngine；斷線重連沒有。換掉的引擎正在念、正在存檔
     * 或正在連的，都先回覆，不留著讓 Dart 一直等。
     */
    private fun createEngine(engine: String?, reply: Result?) {
        if (reply != null) {
            engineReply?.success(0)
            engineReply = reply
        }
        if (speakResult != null) speakCompletion(0)
        if (synthResult != null) synthCompletion(0)
        speaking = false
        synth = false
        currentUtteranceId = null
        ttsStatus = null
        // 換掉的引擎要關掉，不然它和系統朗讀服務的連線一直留著。
        tts?.shutdown()
        val generation = ++engineGeneration
        // 系統在主執行緒回呼（連不上時在建構子裡直接回呼）；排到 [worker] 再處理。
        val created = TextToSpeech(context, { status ->
            onWorker { if (generation == engineGeneration) onEngineReady(status) }
        }, engine)
        tts = created
        connectedEngine = engine ?: created.defaultEngine
    }

    /** 在 [worker] 上執行。 */
    private fun onEngineReady(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts!!.setOnUtteranceProgressListener(progressListener(engineGeneration))
            // nightreader.5：先套預設音色的語言，再跑排著的呼叫；原本順序相反，
            // 引擎連上前送來的 setLanguage 會被蓋回預設語言。
            try {
                val locale: Locale = tts!!.defaultVoice.locale
                if (isLanguageAvailable(locale)) {
                    tts!!.language = locale
                }
            } catch (e: NullPointerException) {
                Log.e(tag, "getDefaultLocale: " + e.message)
            } catch (e: IllegalArgumentException) {
                Log.e(tag, "getDefaultLocale: " + e.message)
            }
        } else {
            Log.e(tag, "Failed to initialize TextToSpeech with status: $status")
        }

        ttsStatus = status
        // 先回覆這個引擎的 setEngine，再跑排著的呼叫：排著的可能是下一次 setEngine，
        // 它會換上自己的回覆。
        engineReply?.let { reply ->
            engineReply = null
            if (status == TextToSpeech.SUCCESS) {
                reply.success(1)
            } else {
                reply.error("TtsError", "Failed to initialize TextToSpeech with status: $status", null)
            }
        }
        // Handle pending method calls (sent while TTS was initializing)
        // 先取出再跑：念不出來的 speak 會重連並把自己排回 pendingMethodCalls。
        val calls = ArrayList(pendingMethodCalls)
        pendingMethodCalls.clear()
        for (call in calls) {
            call.run()
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val mainResult = MainThreadResult(result, handler!!)
        val target = worker
        if (target == null) {
            mainResult.error("TtsError", "flutter_tts is detached", null)
            return
        }
        target.post { runCall(call, mainResult) }
    }

    /** 在 [worker] 上執行；丟出的例外回成這次呼叫的錯誤（見 [guarded]）。 */
    private fun runCall(call: MethodCall, result: Result, allowReconnect: Boolean = true) {
        try {
            handleMethodCall(call, result, allowReconnect)
        } catch (e: Exception) {
            Log.e(tag, "${call.method}: $e")
            result.error("TtsError", "${call.method}: $e", null)
        }
    }

    /** 在 [worker] 上執行。 */
    private fun handleMethodCall(
        call: MethodCall,
        result: Result,
        allowReconnect: Boolean = true,
    ) {
        // If TTS is still loading
        if (ttsStatus == null) {
            // Suspend method call until the TTS engine is ready
            pendingMethodCalls.add(Runnable { runCall(call, result, allowReconnect) })
            return
        }
        when (call.method) {
            "speak" -> {
                var text: String = call.argument("text")!!
                val focus: Boolean = call.argument("focus")!!
                if (pauseText == null) {
                    pauseText = text
                    currentText = pauseText!!
                }
                if (isPaused) {
                    // Ensure the text hasn't changed
                    if (currentText == text) {
                        text = pauseText!!
                    } else {
                        pauseText = text
                        currentText = pauseText!!
                        lastProgress = 0
                    }
                }
                if (speaking) {
                    // If TTS is set to queue mode, allow the utterance to be queued up rather than discarded
                    if (queueMode == TextToSpeech.QUEUE_FLUSH) {
                        result.success(0)
                        return
                    }
                }
                when (speak(text, focus, allowReconnect)) {
                    SpeakOutcome.STARTED -> {}
                    SpeakOutcome.RECONNECTING -> {
                        // 連上後再念這句；換了新引擎還是連不上就回覆失敗，不再
                        // 換一個引擎把它排回去（nightreader.6）。
                        pendingMethodCalls.add(Runnable { runCall(call, result, false) })
                        return
                    }
                    SpeakOutcome.REJECTED -> {
                        // 引擎連著但不收這句，或重連過一次還連不上：直接回覆失敗。
                        result.success(0)
                        return
                    }
                }
                // Only use await speak completion if queueMode is set to QUEUE_FLUSH
                if (awaitSpeakCompletion && queueMode == TextToSpeech.QUEUE_FLUSH) {
                    speaking = true
                    speakResult = result
                } else {
                    result.success(1)
                }
            }

            "awaitSpeakCompletion" -> {
                awaitSpeakCompletion = java.lang.Boolean.parseBoolean(call.arguments.toString())
                result.success(1)
            }

            "awaitSynthCompletion" -> {
                awaitSynthCompletion = java.lang.Boolean.parseBoolean(call.arguments.toString())
                result.success(1)
            }

            "getMaxSpeechInputLength" -> {
                val res = maxSpeechInputLength
                result.success(res)
            }

            "synthesizeToFile" -> {
                val text: String? = call.argument("text")
                if (synth) {
                    result.success(0)
                    return
                }
                val fileName: String? = call.argument("fileName")
                val isFullPath: Boolean? = call.argument("isFullPath")
                synthesizeToFile(text!!, fileName!!, isFullPath!!)
                if (awaitSynthCompletion) {
                    synth = true
                    synthResult = result
                } else {
                    result.success(1)
                }
            }

            "pause" -> {
                isPaused = true
                if (pauseText != null) {
                    pauseText = pauseText!!.substring(lastProgress)
                }
                stop()
                result.success(1)
                if (speakResult != null) {
                    speakResult!!.success(0)
                    speakResult = null
                }
            }

            "stop" -> {
                isPaused = false
                pauseText = null
                stop()
                lastProgress = 0
                result.success(1)
                if (speakResult != null) {
                    speakResult!!.success(0)
                    speakResult = null
                }
            }

            "setEngine" -> {
                val engine: String = call.arguments.toString()
                setEngine(engine, result)
            }

            "setSpeechRate" -> {
                val rate: String = call.arguments.toString()
                // To make the FlutterTts API consistent across platforms,
                // Android 1.0 is mapped to flutter 0.5.
                setSpeechRate(rate.toFloat() * 2.0f)
                result.success(1)
            }

            "setVolume" -> {
                val volume: String = call.arguments.toString()
                setVolume(volume.toFloat(), result)
            }

            "setPitch" -> {
                val pitch: String = call.arguments.toString()
                setPitch(pitch.toFloat(), result)
            }

            "setLanguage" -> {
                val language: String = call.arguments.toString()
                setLanguage(language, result)
            }

            "getLanguages" -> getLanguages(result)
            "getVoices" -> getVoices(result)
            "getSpeechRateValidRange" -> getSpeechRateValidRange(result)
            "getEngines" -> getEngines(result)
            "getDefaultEngine" -> getDefaultEngine(result)
            "getDefaultVoice" -> getDefaultVoice(result)
            "setVoice" -> {
                val voice: HashMap<String?, String>? = call.arguments()
                setVoice(voice!!, result)
            }

            "clearVoice" -> clearVoice(result)

            "isLanguageAvailable" -> {
                val language: String = call.arguments.toString()
                val locale: Locale = Locale.forLanguageTag(language)
                result.success(isLanguageAvailable(locale))
            }

            "setSilence" -> {
                val silencems: String = call.arguments.toString()
                this.silencems = silencems.toInt()
                result.success(1)
            }

            "setSharedInstance" -> result.success(1)
            "isLanguageInstalled" -> {
                val language: String = call.arguments.toString()
                result.success(isLanguageInstalled(language))
            }

            "areLanguagesInstalled" -> {
                val languages: List<String?>? = call.arguments()
                result.success(areLanguagesInstalled(languages!!))
            }

            "setQueueMode" -> {
                val queueMode: String = call.arguments.toString()
                this.queueMode = queueMode.toInt()
                result.success(1)
            }

            "setAudioAttributesForNavigation" -> {
                setAudioAttributesForNavigation()
                result.success(1)
            }

            else -> result.notImplemented()
        }
    }

    private fun setSpeechRate(rate: Float) {
        tts!!.setSpeechRate(rate)
    }

    private fun isLanguageAvailable(locale: Locale?): Boolean {
        return tts!!.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE
    }

    private fun areLanguagesInstalled(languages: List<String?>): Map<String?, Boolean> {
        val result: MutableMap<String?, Boolean> = HashMap()
        for (language in languages) {
            result[language] = isLanguageInstalled(language)
        }
        return result
    }

    private fun isLanguageInstalled(language: String?): Boolean {
        val locale: Locale = Locale.forLanguageTag(language!!)
        if (isLanguageAvailable(locale)) {
            var voiceToCheck: Voice? = null
            for (v in tts!!.voices) {
                if (v.locale == locale && !v.isNetworkConnectionRequired) {
                    voiceToCheck = v
                    break
                }
            }
            if (voiceToCheck != null) {
                val features: Set<String> = voiceToCheck.features
                return (!features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))
            }
        }
        return false
    }

    private fun setEngine(engine: String?, result: Result) {
        // nightreader.5：已經連著同一個引擎就不重連（開 App 套用存下的引擎時，
        // 多半就是系統預設的那個；重連要再等系統的朗讀服務回應一次）。比的是
        // 建立這個引擎時連的那個，不是現在的系統預設（使用者可能剛在系統設定改過）。
        if (ttsStatus == TextToSpeech.SUCCESS && engine != null && engine == connectedEngine) {
            selectedEngine = engine
            result.success(1)
            return
        }
        selectedEngine = engine
        createEngine(engine, result)
    }

    private fun setLanguage(language: String?, result: Result) {
        val locale: Locale = Locale.forLanguageTag(language!!)
        if (isLanguageAvailable(locale)) {
            tts!!.language = locale
            result.success(1)
        } else {
            result.success(0)
        }
    }

    private fun setVoice(voice: HashMap<String?, String>, result: Result) {
        for (ttsVoice in tts!!.voices) {
            if (ttsVoice.name == voice["name"] && ttsVoice.locale
                    .toLanguageTag() == voice["locale"]
            ) {
                tts!!.voice = ttsVoice
                result.success(1)
                return
            }
        }
        Log.d(tag, "Voice name not found: $voice")
        result.success(0)
    }

    private fun clearVoice(result: Result) {
        tts!!.voice = tts!!.defaultVoice
        result.success(1)
    }

    private fun setVolume(volume: Float, result: Result) {
        if (volume in (0.0f..1.0f)) {
            bundle!!.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
            result.success(1)
        } else {
            Log.d(tag, "Invalid volume $volume value - Range is from 0.0 to 1.0")
            result.success(0)
        }
    }

    private fun setPitch(pitch: Float, result: Result) {
        if (pitch in (0.5f..2.0f)) {
            tts!!.setPitch(pitch)
            result.success(1)
        } else {
            Log.d(tag, "Invalid pitch $pitch value - Range is from 0.5 to 2.0")
            result.success(0)
        }
    }

    private fun getVoices(result: Result) {
        val voices = ArrayList<HashMap<String, String>>()
        try {
            for (voice in tts!!.voices) {
                val voiceMap = HashMap<String, String>()
                readVoiceProperties(voiceMap, voice)
                voices.add(voiceMap)
            }
            result.success(voices)
        } catch (e: NullPointerException) {
            Log.d(tag, "getVoices: " + e.message)
            result.success(null)
        }
    }

    private fun getLanguages(result: Result) {
        val locales = ArrayList<String>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // While this method was introduced in API level 21, it seems that it
                // has not been implemented in the speech service side until API Level 23.
                for (locale in tts!!.availableLanguages) {
                    locales.add(locale.toLanguageTag())
                }
            } else {
                for (locale in Locale.getAvailableLocales()) {
                    if (locale.variant.isEmpty() && isLanguageAvailable(locale)) {
                        locales.add(locale.toLanguageTag())
                    }
                }
            }
        } catch (e: MissingResourceException) {
            Log.d(tag, "getLanguages: " + e.message)
        } catch (e: NullPointerException) {
            Log.d(tag, "getLanguages: " + e.message)
        }
        result.success(locales)
    }

    // nightreader.3：一併回傳引擎的顯示名稱（label），設定頁才不必顯示套件名稱。
    private fun getEngines(result: Result) {
        val engines = ArrayList<HashMap<String, String>>()
        try {
            for (engineInfo in tts!!.engines) {
                engines.add(
                    hashMapOf(
                        "name" to engineInfo.name,
                        "label" to (engineInfo.label ?: engineInfo.name),
                    ),
                )
            }
        } catch (e: Exception) {
            Log.d(tag, "getEngines: " + e.message)
        }
        result.success(engines)
    }

    private fun getDefaultEngine(result: Result) {
        val defaultEngine: String? = tts!!.defaultEngine
        result.success(defaultEngine)
    }

    private fun getDefaultVoice(result: Result) {
        val defaultVoice: Voice? = tts!!.defaultVoice
        val voice = HashMap<String, String>()
        if (defaultVoice != null) {
            readVoiceProperties(voice, defaultVoice)
        }
        result.success(voice)
    }
    // Add voice properties into the voice map
    fun readVoiceProperties(map: MutableMap<String, String>, voice: Voice) {
        map["name"] = voice.name
        map["locale"] = voice.locale.toLanguageTag()
        map["quality"] = qualityToString(voice.quality)
        map["latency"] = latencyToString(voice.latency)
        map["network_required"] = if (voice.isNetworkConnectionRequired) "1" else "0"
        map["features"] = voice.features.joinToString(separator = "\t")
        
    }

    // Function to map quality integer to the constant name
    fun qualityToString(quality: Int): String {
        return when (quality) {
            Voice.QUALITY_VERY_HIGH -> "very high"
            Voice.QUALITY_HIGH -> "high"
            Voice.QUALITY_NORMAL -> "normal"
            Voice.QUALITY_LOW -> "low"
            Voice.QUALITY_VERY_LOW -> "very low"
            else -> "unknown"
        }
    }
    // Function to map latency integer to the constant name
    fun latencyToString(quality: Int): String {
        return when (quality) {
            Voice.LATENCY_VERY_HIGH -> "very high"
            Voice.LATENCY_HIGH -> "high"
            Voice.LATENCY_NORMAL -> "normal"
            Voice.LATENCY_LOW -> "low"
            Voice.LATENCY_VERY_LOW -> "very low"
            else -> "unknown"
        }
    }

    private fun getSpeechRateValidRange(result: Result) {
        // Valid values available in the android documentation.
        // https://developer.android.com/reference/android/speech/tts/TextToSpeech#setSpeechRate(float)
        // To make the FlutterTts API consistent across platforms,
        // we map Android 1.0 to flutter 0.5 and so on.
        val data = HashMap<String, String>()
        data["min"] = "0"
        data["normal"] = "0.5"
        data["max"] = "1.5"
        data["platform"] = "android"
        result.success(data)
    }

    private enum class SpeakOutcome { STARTED, RECONNECTING, REJECTED }

    private fun speak(text: String, focus: Boolean, allowReconnect: Boolean): SpeakOutcome {
        if (!ismServiceConnectionUsable(tts)) {
            // nightreader.6：重連只留一次。換了新引擎還是連不上就把這句回成
            // 失敗，不再換一個引擎、把它排回去，不然會一直重連、Dart 一直等。
            if (!allowReconnect) return SpeakOutcome.REJECTED
            createEngine(selectedEngine, null)
            return SpeakOutcome.RECONNECTING
        }
        val uuid: String = UUID.randomUUID().toString()
        utterances[uuid] = text
        if(focus){
            requestAudioFocus()
        }
        // 送出之前就記下：很短的一句可能在 speak 回來之前就念完，回呼在別的
        // 執行緒，晚記會把這一句自己的完成當成舊句丟掉。
        val previousUtteranceId = currentUtteranceId
        currentUtteranceId = uuid
        val accepted = if (silencems > 0) {
            tts!!.playSilentUtterance(
                silencems.toLong(),
                TextToSpeech.QUEUE_FLUSH,
                SILENCE_PREFIX + uuid
            )
            tts!!.speak(text, TextToSpeech.QUEUE_ADD, bundle, uuid) == 0
        } else {
            tts!!.speak(text, queueMode, bundle, uuid) == 0
        }
        if (accepted) return SpeakOutcome.STARTED
        currentUtteranceId = previousUtteranceId
        utterances.remove(uuid)
        return SpeakOutcome.REJECTED
    }

    private fun stop() {
        if (awaitSynthCompletion) synth = false
        if (awaitSpeakCompletion) speaking = false
        tts!!.stop()
    }

    private val maxSpeechInputLength: Int
        get() = TextToSpeech.getMaxSpeechInputLength()

    private fun closeParcelFileDescriptor(isError: Boolean)  {
        if (this.parcelFileDescriptor != null)  {
            if (isError) {
                this.parcelFileDescriptor!!.closeWithError("Error synthesizing TTS to file")
            } else {
                this.parcelFileDescriptor!!.close()
            }
        }
    }

    private fun synthesizeToFile(text: String, fileName: String, isFullPath: Boolean) {
        val fullPath: String
        val uuid: String = UUID.randomUUID().toString()
        bundle!!.putString(
            TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID,
            SYNTHESIZE_TO_FILE_PREFIX + uuid
        )

        val result: Int =
            if(isFullPath){
                val file = File(fileName)
                fullPath = file.path

                tts!!.synthesizeToFile(text, bundle!!, file!!, SYNTHESIZE_TO_FILE_PREFIX + uuid)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val resolver = this.context?.contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "audio/wav")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MUSIC)
                }
                val uri = resolver?.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, contentValues)
                this.parcelFileDescriptor = resolver?.openFileDescriptor(uri!!, "rw")
                fullPath = uri?.path + File.separatorChar + fileName

                tts!!.synthesizeToFile(text, bundle!!, parcelFileDescriptor!!, SYNTHESIZE_TO_FILE_PREFIX + uuid)
            } else {
                val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                val file = File(musicDir, fileName)
                fullPath = file.path

                tts!!.synthesizeToFile(text, bundle!!, file!!, SYNTHESIZE_TO_FILE_PREFIX + uuid)
            }

        if (result == TextToSpeech.SUCCESS) {
            Log.d(tag, "Successfully created file : $fullPath")
        } else {
            Log.d(tag, "Failed creating file : $fullPath")
        }
    }

    private fun invokeMethod(method: String, arguments: Any) {
        handler!!.post {
            if (methodChannel != null) methodChannel!!.invokeMethod(
                method,
                arguments
            )
        }
    }

    private fun ismServiceConnectionUsable(tts: TextToSpeech?): Boolean {
        var isBindConnection = true
        if (tts == null) {
            return false
        }
        val fields: Array<Field> = tts.javaClass.declaredFields
        for (j in fields.indices) {
            fields[j].isAccessible = true
            if ("mServiceConnection" == fields[j].name && "android.speech.tts.TextToSpeech\$Connection" == fields[j].type.name) {
                try {
                    if (fields[j][tts] == null) {
                        isBindConnection = false
                        Log.e(tag, "*******TTS -> mServiceConnection == null*******")
                    }
                } catch (e: IllegalArgumentException) {
                    e.printStackTrace()
                } catch (e: IllegalAccessException) {
                    e.printStackTrace()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        return isBindConnection
    }

    // Method to set AudioAttributes for navigation usage
    private fun setAudioAttributesForNavigation() {
        if (tts != null) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            tts!!.setAudioAttributes(audioAttributes)
        }
    }

    private fun requestAudioFocus() {
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setOnAudioFocusChangeListener { /* opcional para monitorar mudanças de foco */ }
                .build()
            audioManager?.requestAudioFocus(audioFocusRequest!!)
        } else {
            audioManager?.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    private fun releaseAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            audioManager?.abandonAudioFocus(null)
        }
    }
}

/**
 * 結果一律在主執行緒回給 Dart：呼叫在 [FlutterTtsPlugin] 的背景執行緒上做完。
 * 只回第一次：同一個呼叫回兩次，Flutter 會丟出 Reply already submitted。
 */
private class MainThreadResult(
    private val result: Result,
    private val main: Handler,
) : Result {
    private val replied = java.util.concurrent.atomic.AtomicBoolean(false)

    private fun reply(send: () -> Unit) {
        if (replied.compareAndSet(false, true)) main.post(send)
    }

    override fun success(value: Any?) = reply { result.success(value) }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
        reply { result.error(errorCode, errorMessage, errorDetails) }

    override fun notImplemented() = reply { result.notImplemented() }
}
