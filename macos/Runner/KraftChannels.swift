import AVFoundation
import AudioToolbox
import CoreAudio
import FlutterMacOS
import Foundation
import Security
import Speech

/// Los canales de KRAFT que también existen en el Mac: llavero, dictado y voz.
enum KraftChannels {
  private static var speech: KraftMacSpeech?
  private static var voice: KraftMacVoiceAudio?
  private static var registered: [AnyObject] = []
  private static var widgets: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let secure = FlutterMethodChannel(name: "kraft/secure", binaryMessenger: messenger)
    secure.setMethodCallHandler { call, result in KraftMacKeychain.handle(call, result: result) }

    let dictation = KraftMacSpeech()
    speech = dictation
    let speechChannel = FlutterMethodChannel(name: "kraft/speech", binaryMessenger: messenger)
    speechChannel.setMethodCallHandler { call, result in dictation.handle(call, result: result) }
    let speechText = FlutterEventChannel(name: "kraft/speech/text", binaryMessenger: messenger)
    speechText.setStreamHandler(dictation)

    let liveVoice = KraftMacVoiceAudio()
    voice = liveVoice
    let voiceChannel = FlutterMethodChannel(name: "kraft/voice", binaryMessenger: messenger)
    voiceChannel.setMethodCallHandler { call, result in liveVoice.handle(call, result: result) }
    let micChannel = FlutterEventChannel(name: "kraft/voice/mic", binaryMessenger: messenger)
    micChannel.setStreamHandler(liveVoice)

    let output = KraftSpeechOutput()
    let outputChannel = FlutterMethodChannel(name: "kraft/tts", binaryMessenger: messenger)
    outputChannel.setMethodCallHandler { call, result in output.handle(call, result: result) }

    let widgets = FlutterMethodChannel(name: "kraft/widgets", binaryMessenger: messenger)
    widgets.setMethodCallHandler { call, result in
      if call.method == "syncPending" {
        let items = (call.arguments as? [String: Any])?["items"] ?? []
        UserDefaults.standard.set(items, forKey: "pendingItems")
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    self.widgets = widgets

    registered = [secure, speechChannel, speechText, voiceChannel, micChannel, outputChannel, widgets]
  }

  static func capture() { widgets?.invokeMethod("capture", arguments: nil) }
}

/// Entrada/salida PCM para Gemini Live en macOS.
/// Micrófono y altavoz van en motores distintos: un solo `AVAudioEngine` arma un
/// dispositivo agregado y revienta con -10875 cuando la entrada y la salida
/// tienen distinta frecuencia (AirPods, interfaces, HDMI…).
final class KraftMacVoiceAudio: NSObject, FlutterStreamHandler {
  private let capture = AVAudioEngine()
  private let playback = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  /// Mono no intercalado: `int16ChannelData` es nil si el formato va intercalado, y se tiraba todo el mic.
  private let geminiPcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
  private var playerFormat: AVAudioFormat?
  private var playbackConverter: AVAudioConverter?
  private var captureConverter: AVAudioConverter?
  private var captureFormat: AVAudioFormat?
  private var captureSinkNode: AVAudioSinkNode?
  private var playerAttached = false
  private var sink: FlutterEventSink?
  private var running = false

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "listMicrophones":
      do { result(try KraftMacAudioDevices.inputs()) }
      catch { result(FlutterError(code: "audio_devices", message: error.localizedDescription, details: nil)) }
    case "start":
      let microphoneID = (call.arguments as? [String: Any])?["microphoneId"] as? String
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          guard granted else { result(false); return }
          do { try self.start(microphoneID: microphoneID); result(true) }
          catch { self.stop(); result(FlutterError(code: "audio", message: KraftAudioGuard.explain(error), details: nil)) }
        }
      }
    case "stop": stop(); result(nil)
    case "play":
      if let data = (call.arguments as? FlutterStandardTypedData)?.data { play(data) }
      result(nil)
    case "clear": player.stop(); if running { player.play() }; result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(microphoneID: String?) throws {
    if running { return }
    try startCapture(microphoneID: microphoneID)
    try startPlayback()
    player.play()
    running = true
  }

  private func startCapture(microphoneID: String?) throws {
    let input = capture.inputNode
    try KraftMacAudioDevices.select(microphoneID, for: input)
    var inputFormat = input.inputFormat(forBus: 0)
    // Cambiar de dispositivo deja el formato en blanco hasta que el motor se
    // reconfigura: se le da una pasada de `reset` antes de darlo por perdido.
    if !inputFormat.isUsableForCapture {
      capture.reset()
      inputFormat = input.inputFormat(forBus: 0)
    }
    if !inputFormat.isUsableForCapture {
      inputFormat = input.outputFormat(forBus: 0)
    }
    try KraftAudioGuard.check(inputFormat)
    guard let converter = AVAudioConverter(from: inputFormat, to: KraftAudioGuard.micPcm) else {
      throw NSError(domain: "KraftMacVoiceAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no soportado"])
    }
    captureConverter = converter
    captureFormat = inputFormat
    // Un motor solo de captura no tira del hardware si no hay un nodo que consuma
    // la entrada. `AVAudioSinkNode` la drena sin abrir el altavoz (y sin el
    // agregado duplex que reventaba con -10875).
    let sinkNode = AVAudioSinkNode { [weak self] _, frameCount, audioBufferList -> OSStatus in
      guard let self,
            frameCount > 0,
            let format = self.captureFormat,
            let converter = self.captureConverter,
            let inBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
      else { return noErr }
      inBuffer.frameLength = frameCount
      let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
      let dst = UnsafeMutableAudioBufferListPointer(inBuffer.mutableAudioBufferList)
      for (from, to) in zip(src, dst) {
        guard let fromData = from.mData, let toData = to.mData else { continue }
        memcpy(toData, fromData, min(Int(from.mDataByteSize), Int(to.mDataByteSize)))
      }
      guard let data = KraftAudioGuard.convertToMicPcm(inBuffer, converter: converter) else { return noErr }
      DispatchQueue.main.async { self.sink?(FlutterStandardTypedData(bytes: data)) }
      return noErr
    }
    capture.attach(sinkNode)
    capture.connect(input, to: sinkNode, format: inputFormat)
    captureSinkNode = sinkNode
    capture.prepare()
    try capture.start()
  }

  private func startPlayback() throws {
    let hardware = playback.outputNode.outputFormat(forBus: 0)
    let playFormat = KraftAudioGuard.monoFloat(sampleRate: hardware.sampleRate)
    playerFormat = playFormat
    playbackConverter = AVAudioConverter(from: geminiPcm, to: playFormat)
    if !playerAttached {
      playback.attach(player)
      playerAttached = true
    }
    playback.connect(player, to: playback.mainMixerNode, format: playFormat)
    playback.prepare()
    try playback.start()
  }

  private func play(_ data: Data) {
    let frames = data.count / 2
    guard running, frames > 0,
          let converter = playbackConverter,
          let destFormat = playerFormat,
          let source = AVAudioPCMBuffer(pcmFormat: geminiPcm, frameCapacity: AVAudioFrameCount(frames)),
          let ints = source.int16ChannelData
    else { return }
    source.frameLength = AVAudioFrameCount(frames)
    data.withUnsafeBytes { raw in
      for i in 0..<frames {
        ints[0][i] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
      }
    }
    let destFrames = AVAudioFrameCount(Double(frames) * destFormat.sampleRate / geminiPcm.sampleRate) + 32
    guard let dest = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: destFrames) else { return }
    var consumed = false
    var error: NSError?
    converter.convert(to: dest, error: &error) { _, status in
      if consumed { status.pointee = .noDataNow; return nil }
      consumed = true
      status.pointee = .haveData
      return source
    }
    if error == nil, dest.frameLength > 0 {
      player.scheduleBuffer(dest, completionHandler: nil)
    }
  }

  func stop() {
    if let sinkNode = captureSinkNode {
      capture.disconnectNodeInput(sinkNode)
      capture.detach(sinkNode)
      captureSinkNode = nil
    }
    capture.inputNode.removeTap(onBus: 0)
    player.stop()
    if playerAttached {
      playback.detach(player)
      playerAttached = false
    }
    if playback.isRunning { playback.stop() }
    if capture.isRunning { capture.stop() }
    playback.reset()
    capture.reset()
    playbackConverter = nil
    captureConverter = nil
    captureFormat = nil
    playerFormat = nil
    running = false
  }
}

/// Descubre las entradas Core Audio y aplica una al Audio Unit de entrada sin
/// cambiar el micrófono predeterminado del resto del sistema.
private enum KraftMacAudioDevices {
  static func inputs() throws -> [[String: Any]] {
    let defaultID = try defaultInputID()
    return try allDeviceIDs().compactMap { id in
      guard hasInput(id),
            let uid = try? stringProperty(kAudioDevicePropertyDeviceUID, of: id),
            let name = try? stringProperty(kAudioObjectPropertyName, of: id)
      else { return nil }
      return ["id": uid, "name": name, "default": id == defaultID]
    }.sorted { left, right in
      (left["default"] as? Bool == true) && (right["default"] as? Bool != true)
    }
  }

  /// Sin micrófono concreto no se toca nada: `AAudioUnitSetProperty` sobre
  /// `CurrentDevice` invalida el formato del nodo hasta que el motor se reconfigura,
  /// y el motor ya viene apuntando al dispositivo por defecto del sistema. Forzarlo
  /// era pedir un formato vacío y reventar en `installTap`.
  static func select(_ uid: String?, for input: AVAudioInputNode) throws {
    guard let uid else { return }
    let deviceID: AudioDeviceID
    if let selected = try allDeviceIDs().first(where: {
      (try? stringProperty(kAudioDevicePropertyDeviceUID, of: $0)) == uid
    }) {
      deviceID = selected
    } else {
      // El micrófono guardado ya no está: se deja el del sistema.
      return
    }
    guard let unit = input.audioUnit else {
      throw error("No se pudo acceder al dispositivo de entrada.")
    }
    var selected = deviceID
    let status = AudioUnitSetProperty(
      unit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &selected,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
      throw error("No se pudo seleccionar el micrófono (\(status)).")
    }
  }

  private static func allDeviceIDs() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    )
    guard status == noErr else { throw error("No se pudieron enumerar los micrófonos (\(status)).") }
    var devices = [AudioDeviceID](
      repeating: 0,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size
    )
    status = devices.withUnsafeMutableBytes { buffer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        buffer.baseAddress!
      )
    }
    guard status == noErr else { throw error("No se pudieron leer los micrófonos (\(status)).") }
    return devices
  }

  private static func defaultInputID() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
    )
    guard status == noErr, device != 0 else {
      throw error("No hay un micrófono predeterminado disponible.")
    }
    return device
  }

  private static func hasInput(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func stringProperty(
    _ selector: AudioObjectPropertySelector,
    of device: AudioDeviceID
  ) throws -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    guard status == noErr else { throw error("No se pudo leer un dispositivo de audio (\(status)).") }
    return value as String
  }

  private static func error(_ message: String) -> NSError {
    NSError(domain: "KraftMacAudioDevices", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}

/// Síntesis nativa para las respuestas de Gemini escrito y los modelos locales.
final class KraftSpeechOutput: NSObject {
  private let speaker = AVSpeechSynthesizer()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      let args = call.arguments as? [String: Any] ?? [:]
      let text = (args["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { result(nil); return }
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = AVSpeechSynthesisVoice(language: args["locale"] as? String ?? "es-ES")
      speaker.stopSpeaking(at: .immediate); speaker.speak(utterance); result(nil)
    case "stop": speaker.stopSpeaking(at: .immediate); result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
}

/// La API key de Gemini, guardada en el llavero del Mac.
enum KraftMacKeychain {
  private static let service = "com.arbe.kraft"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let key = arguments["key"] as? String else {
      result(FlutterError(code: "args", message: "Falta la clave", details: nil))
      return
    }
    switch call.method {
    case "read":
      result(read(key))
    case "write":
      write(key, value: arguments["value"] as? String ?? "")
      result(true)
    case "delete":
      delete(key)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func query(_ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
  }

  private static func read(_ key: String) -> String? {
    var request = query(key)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func write(_ key: String, value: String) {
    delete(key)
    var request = query(key)
    request[kSecValueData as String] = Data(value.utf8)
    SecItemAdd(request as CFDictionary, nil)
  }

  private static func delete(_ key: String) {
    SecItemDelete(query(key) as CFDictionary)
  }
}

/// Dictado en el Mac, igual que en el iPad: SpeechAnalyzer en macOS 26 y SFSpeechRecognizer antes.
final class KraftMacSpeech: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private let engine = AVAudioEngine()
  private var running = false
  private var session: AnyObject?
  private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
  private var legacyTask: SFSpeechRecognitionTask?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(mode(for: locale(from: call.arguments)))
    case "start":
      self.stop()
      let wanted = locale(from: call.arguments)
      let chosen = mode(for: wanted)
      guard chosen != "none" else {
        result(false)
        return
      }
      authorize(needsSpeech: chosen == "legacy") { [weak self] granted in
        guard let self else { return }
        guard granted else {
          result(false)
          return
        }
        do {
          if #available(macOS 26.0, *), chosen == "analyzer" {
            try self.startAnalyzer(locale: wanted)
          } else {
            try self.startLegacy(locale: wanted)
          }
          result(true)
        } catch {
          self.stop()
          result(FlutterError(code: "speech", message: error.localizedDescription, details: nil))
        }
      }
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func mode(for wanted: Locale) -> String {
    if #available(macOS 26.0, *), SpeechTranscriber.isAvailable { return "analyzer" }
    if SFSpeechRecognizer(locale: wanted)?.isAvailable == true { return "legacy" }
    return "none"
  }

  private func locale(from arguments: Any?) -> Locale {
    guard let identifier = (arguments as? [String: Any])?["locale"] as? String, !identifier.isEmpty else {
      return Locale.current
    }
    return Locale(identifier: identifier)
  }

  private func authorize(needsSpeech: Bool, _ done: @escaping (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      guard granted else {
        DispatchQueue.main.async { done(false) }
        return
      }
      guard needsSpeech else {
        DispatchQueue.main.async { done(true) }
        return
      }
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async { done(status == .authorized) }
      }
    }
  }

  private func emit(text: String, isFinal: Bool) {
    DispatchQueue.main.async { self.sink?(["text": text, "final": isFinal]) }
  }

  private func emit(error: Error) {
    DispatchQueue.main.async {
      self.sink?(FlutterError(code: "speech", message: error.localizedDescription, details: nil))
    }
  }

  @available(macOS 26.0, *)
  private func startAnalyzer(locale wanted: Locale) throws {
    if running { return }
    running = true
    let session = KraftMacAnalyzerSession(
      onText: { [weak self] text, isFinal in self?.emit(text: text, isFinal: isFinal) },
      onError: { [weak self] error in self?.emit(error: error) }
    )
    self.session = session
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    try KraftAudioGuard.check(inputFormat)
    Task {
      do {
        let target = try await session.prepare(locale: wanted)
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
          throw NSError(domain: "KraftSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no soportado"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
          let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / inputFormat.sampleRate) + 64
          guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
          var consumed = false
          var error: NSError?
          converter.convert(to: out, error: &error) { _, status in
            if consumed {
              status.pointee = .noDataNow
              return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
          }
          guard error == nil, out.frameLength > 0 else { return }
          session.feed(out)
        }
        self.engine.prepare()
        try self.engine.start()
      } catch {
        self.emit(error: error)
        self.stop()
      }
    }
  }

  private func startLegacy(locale wanted: Locale) throws {
    if running { return }
    guard let recognizer = SFSpeechRecognizer(locale: wanted) else {
      throw NSError(domain: "KraftSpeech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Idioma no disponible para el dictado"])
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
    legacyRequest = request
    legacyTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      if let result {
        self?.emit(text: result.bestTranscription.formattedString, isFinal: result.isFinal)
      }
      if let error { self?.emit(error: error) }
    }
    let input = engine.inputNode
    let legacyFormat = input.outputFormat(forBus: 0)
    try KraftAudioGuard.check(legacyFormat)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 4096, format: legacyFormat) { buffer, _ in
      request.append(buffer)
    }
    engine.prepare()
    try engine.start()
    running = true
  }

  func stop() {
    // El tap se quita SIEMPRE, aunque `running` sea false: si `start` falló después
    // de instalarlo (por ejemplo en `engine.start()`), se quedaba puesto y el
    // siguiente intento reventaba al instalar un segundo tap en el mismo bus.
    // `removeTap` sobre un bus limpio no hace nada.
    engine.inputNode.removeTap(onBus: 0)
    if engine.isRunning { engine.stop() }
    engine.reset()
    legacyRequest?.endAudio()
    legacyRequest = nil
    legacyTask?.cancel()
    legacyTask = nil
    if #available(macOS 26.0, *), let session = session as? KraftMacAnalyzerSession { session.finish() }
    session = nil
    running = false
  }
}

@available(macOS 26.0, *)
final class KraftMacAnalyzerSession {
  init(onText: @escaping (String, Bool) -> Void, onError: @escaping (Error) -> Void) {
    self.onText = onText
    self.onError = onError
  }

  private let onText: (String, Bool) -> Void
  private let onError: (Error) -> Void
  private var analyzer: SpeechAnalyzer?
  private var continuation: AsyncStream<AnalyzerInput>.Continuation?
  private var results: Task<Void, Never>?

  func prepare(locale wanted: Locale) async throws -> AVAudioFormat {
    var locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted)
    if locale == nil {
      let supported = await SpeechTranscriber.supportedLocales
      locale = supported.first(where: { $0.identifier.hasPrefix("es") }) ?? supported.first
    }
    let chosen = locale ?? Locale(identifier: "en-US")
    let transcriber = SpeechTranscriber(locale: chosen, preset: .progressiveTranscription)
    if await AssetInventory.status(forModules: [transcriber]) != .installed,
       let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await request.downloadAndInstall()
    }
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw NSError(domain: "KraftSpeech", code: 3, userInfo: [NSLocalizedDescriptionKey: "El dictado no aceptó el micrófono"])
    }
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    self.continuation = continuation
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.analyzer = analyzer
    results = Task { [onText, onError] in
      var settled = ""
      do {
        for try await result in transcriber.results {
          let piece = String(result.text.characters)
          if result.isFinal {
            settled += piece
            onText(settled, true)
          } else {
            onText(settled + piece, false)
          }
        }
      } catch {
        onError(error)
      }
    }
    try await analyzer.start(inputSequence: stream)
    return format
  }

  func feed(_ buffer: AVAudioPCMBuffer) {
    continuation?.yield(AnalyzerInput(buffer: buffer))
  }

  func finish() {
    results?.cancel()
    results = nil
    continuation?.finish()
    continuation = nil
    let analyzer = self.analyzer
    self.analyzer = nil
    Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
  }
}

extension AVAudioFormat {
  /// `installTap(onBus:bufferSize:format:)` lanza una NSException con un formato
  /// vacío, y una NSException no se puede capturar desde Swift: la app aborta de
  /// golpe. Hay que comprobarlo antes.
  var isUsableForCapture: Bool { sampleRate > 0 && channelCount > 0 }
}

enum KraftAudioGuard {
  /// `kAudioUnitErr_FailedInitialization`: el grafo no pudo abrir el hardware.
  private static let failedInitialization = -10875

  /// PCM 16 kHz mono para Gemini Live. No intercalado: si no, `int16ChannelData` es nil.
  static let micPcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

  static func check(_ format: AVAudioFormat) throws {
    guard format.isUsableForCapture else {
      throw NSError(
        domain: "KraftAudio",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "No hay ningún micrófono disponible. Revisa la entrada de audio en Ajustes del Sistema."
        ]
      )
    }
  }

  static func monoFloat(sampleRate: Double) -> AVAudioFormat {
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: sampleRate > 0 ? sampleRate : 48000,
      channels: 1,
      interleaved: false
    )!
  }

  static func convertToMicPcm(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) -> Data? {
    let ratio = micPcm.sampleRate / max(buffer.format.sampleRate, 1)
    let capacity = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio + 256))
    guard let out = AVAudioPCMBuffer(pcmFormat: micPcm, frameCapacity: capacity) else { return nil }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: out, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }
    if status == .error || error != nil { return nil }
    return int16le(out)
  }

  static func int16le(_ buffer: AVAudioPCMBuffer) -> Data? {
    let frames = Int(buffer.frameLength)
    guard frames > 0 else { return nil }
    if let channels = buffer.int16ChannelData {
      return Data(bytes: channels[0], count: frames * MemoryLayout<Int16>.size)
    }
    let packet = buffer.audioBufferList.pointee.mBuffers
    guard let data = packet.mData, packet.mDataByteSize > 0 else { return nil }
    return Data(bytes: data, count: min(Int(packet.mDataByteSize), frames * MemoryLayout<Int16>.size))
  }

  static func explain(_ error: Error) -> String {
    let ns = error as NSError
    if ns.code == failedInitialization {
      return "No se pudo arrancar el micrófono. Cierra otras apps que lo estén usando, o prueba sin auriculares, y vuelve a intentar."
    }
    return error.localizedDescription
  }
}
