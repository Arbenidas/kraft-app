import AVFoundation
import EventKit
import Flutter
import Security
import Speech
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UIPencilInteractionDelegate {
  private var pencilChannel: FlutterMethodChannel?
  private var widgetsChannel: FlutterMethodChannel?
  private var platformChannels: [AnyObject] = []
  private let reminders = KraftReminders()
  private let voice = KraftVoiceAudio()
  private let speechOutput = KraftSpeechOutput()
  private let speech = KraftSpeech()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Las notificaciones también se muestran con la app abierta.
    UNUserNotificationCenter.current().delegate = self
    attachPencilInteraction()
    return launched
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  /// Canales propios: recordatorios (`kraft/reminders`), llavero (`kraft/secure`) y audio de voz (`kraft/voice`).
  private func attachPlatformChannels(_ messenger: FlutterBinaryMessenger) {
    let remindersChannel = FlutterMethodChannel(name: "kraft/reminders", binaryMessenger: messenger)
    remindersChannel.setMethodCallHandler { [reminders] call, result in reminders.handle(call, result: result) }
    let secureChannel = FlutterMethodChannel(name: "kraft/secure", binaryMessenger: messenger)
    secureChannel.setMethodCallHandler { call, result in KraftKeychain.handle(call, result: result) }
    let voiceChannel = FlutterMethodChannel(name: "kraft/voice", binaryMessenger: messenger)
    voiceChannel.setMethodCallHandler { [voice] call, result in voice.handle(call, result: result) }
    let micChannel = FlutterEventChannel(name: "kraft/voice/mic", binaryMessenger: messenger)
    micChannel.setStreamHandler(voice)
    let outputChannel = FlutterMethodChannel(name: "kraft/tts", binaryMessenger: messenger)
    outputChannel.setMethodCallHandler { [speechOutput] call, result in speechOutput.handle(call, result: result) }
    let speechChannel = FlutterMethodChannel(name: "kraft/speech", binaryMessenger: messenger)
    speechChannel.setMethodCallHandler { [speech] call, result in speech.handle(call, result: result) }
    let speechText = FlutterEventChannel(name: "kraft/speech/text", binaryMessenger: messenger)
    speechText.setStreamHandler(speech)
    let widgetsChannel = FlutterMethodChannel(name: "kraft/widgets", binaryMessenger: messenger)
    widgetsChannel.setMethodCallHandler { call, result in
      if call.method == "syncPending" {
        let items = (call.arguments as? [String: Any])?["items"] ?? []
        UserDefaults.standard.set(items, forKey: "pendingItems")
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    self.widgetsChannel = widgetsChannel
    platformChannels = [remindersChannel, secureChannel, voiceChannel, micChannel, outputChannel, speechChannel, speechText, widgetsChannel]
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.scheme == "kraft", url.host == "capture" {
      widgetsChannel?.invokeMethod("capture", arguments: nil)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// Registra el doble toque (y el apretón en Apple Pencil Pro) y lo envía a Flutter por `kraft/pencil`.
  private func attachPencilInteraction() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // El controlador del storyboard aún no está listo: reintenta en el siguiente ciclo.
      DispatchQueue.main.async { [weak self] in
        if self?.pencilChannel == nil, self?.window?.rootViewController is FlutterViewController {
          self?.attachPencilInteraction()
        }
      }
      return
    }
    pencilChannel = FlutterMethodChannel(name: "kraft/pencil", binaryMessenger: controller.binaryMessenger)
    attachPlatformChannels(controller.binaryMessenger)
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    controller.view.addInteraction(interaction)
  }

  // iOS 12.1 – 17.4
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    sendPencil("tap", action: UIPencilInteraction.preferredTapAction)
  }

  // iOS 17.5+: sustituye a pencilInteractionDidTap.
  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    sendPencil("tap", action: UIPencilInteraction.preferredTapAction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
    guard squeeze.phase == .ended else { return }
    sendPencil("squeeze", action: UIPencilInteraction.preferredSqueezeAction)
  }

  private func sendPencil(_ method: String, action: UIPencilPreferredAction) {
    pencilChannel?.invokeMethod(method, arguments: ["action": Self.name(of: action)])
  }

  private static func name(of action: UIPencilPreferredAction) -> String {
    switch action {
    case .ignore: return "ignore"
    case .switchEraser: return "switchEraser"
    case .switchPrevious: return "switchPrevious"
    case .showColorPalette: return "showColorPalette"
    default:
      if #available(iOS 17.5, *) {
        switch action {
        case .showInkAttributes: return "showInkAttributes"
        case .showContextualPalette: return "showContextualPalette"
        case .runSystemShortcut: return "runSystemShortcut"
        default: break
        }
      }
      return "switchEraser"
    }
  }
}

// MARK: - Recordatorios

/// Notificaciones locales para las tareas con hora y sincronización con la app Recordatorios.
final class KraftReminders {
  private let store = EKEventStore()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "authorizeNotifications":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "schedule":
      guard let id = args["id"] as? String, let title = args["title"] as? String, let at = args["at"] as? NSNumber else {
        result(FlutterError(code: "args", message: "Faltan id, title o at", details: nil))
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = args["body"] as? String ?? ""
      content.sound = .default
      let date = Date(timeIntervalSince1970: at.doubleValue / 1000)
      let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
      let request = UNNotificationRequest(
        identifier: id,
        content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      )
      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async { result(error == nil) }
      }
    case "cancel":
      let ids = args["ids"] as? [String] ?? []
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
      result(nil)
    case "authorizeReminders":
      if #available(iOS 17.0, *) {
        store.requestFullAccessToReminders { granted, _ in DispatchQueue.main.async { result(granted) } }
      } else {
        store.requestAccess(to: .reminder) { granted, _ in DispatchQueue.main.async { result(granted) } }
      }
    case "saveReminder":
      guard remindersAuthorized else {
        result(nil)
        return
      }
      let existing = (args["identifier"] as? String).flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
      let reminder = existing ?? EKReminder(eventStore: store)
      if reminder.calendar == nil { reminder.calendar = store.defaultCalendarForNewReminders() }
      reminder.title = args["title"] as? String ?? ""
      reminder.notes = args["notes"] as? String
      reminder.isCompleted = args["done"] as? Bool ?? false
      if let at = args["at"] as? NSNumber {
        let date = Date(timeIntervalSince1970: at.doubleValue / 1000)
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      } else {
        reminder.dueDateComponents = nil
      }
      // Sin alarma propia: el aviso lo da KRAFT, así no llegan dos notificaciones.
      reminder.alarms = nil
      do {
        try store.save(reminder, commit: true)
        result(reminder.calendarItemIdentifier)
      } catch {
        result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
      }
    case "deleteReminder":
      if remindersAuthorized, let id = args["identifier"] as? String, let item = store.calendarItem(withIdentifier: id) as? EKReminder {
        try? store.remove(item, commit: true)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var remindersAuthorized: Bool {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if #available(iOS 17.0, *) { return status == .fullAccess }
    return status == .authorized
  }
}

// MARK: - Llavero

/// Guarda secretos (la API key de Gemini) en el llavero del iPad, no en la base de datos.
enum KraftKeychain {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let key = args["key"] as? String else {
      result(FlutterError(code: "args", message: "Falta key", details: nil))
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.arbe.kraft",
      kSecAttrAccount as String: key,
    ]
    switch call.method {
    case "read":
      var item: CFTypeRef?
      var read = query
      read[kSecReturnData as String] = true
      read[kSecMatchLimit as String] = kSecMatchLimitOne
      let status = SecItemCopyMatching(read as CFDictionary, &item)
      if status == errSecSuccess, let data = item as? Data {
        result(String(data: data, encoding: .utf8))
      } else {
        result(nil)
      }
    case "write":
      SecItemDelete(query as CFDictionary)
      var add = query
      add[kSecValueData as String] = Data((args["value"] as? String ?? "").utf8)
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      result(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
    case "delete":
      SecItemDelete(query as CFDictionary)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Audio de voz

/// Micrófono a 16 kHz y reproducción a 24 kHz (PCM 16 bits) para Gemini Live, con la cancelación de eco
/// del sistema: la IA no se escucha a sí misma por el altavoz.
final class KraftVoiceAudio: NSObject, FlutterStreamHandler {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var sink: FlutterEventSink?
  private var running = false
  private var playerAttached = false
  private var playerFormat: AVAudioFormat?
  private var playbackConverter: AVAudioConverter?
  private let geminiPcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!

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
    case "listMicrophones":
      do { result(try listMicrophones()) }
      catch { result(FlutterError(code: "audio_devices", message: error.localizedDescription, details: nil)) }
    case "start":
      let microphoneID = (call.arguments as? [String: Any])?["microphoneId"] as? String
      requestPermission { granted in
        guard granted else {
          result(false)
          return
        }
        do {
          try self.start(microphoneID: microphoneID)
          result(true)
        } catch {
          self.stop()
          result(FlutterError(code: "audio", message: KraftAudioGuard.explain(error), details: nil))
        }
      }
    case "stop":
      stop()
      result(nil)
    case "play":
      if let data = (call.arguments as? FlutterStandardTypedData)?.data { play(data) }
      result(nil)
    case "clear":
      // Interrupción: se corta lo que la IA estaba diciendo.
      player.stop()
      if running { player.play() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func listMicrophones() throws -> [[String: Any]] {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
    return (session.availableInputs ?? []).map { input in
      ["id": input.uid, "name": input.portName]
    }
  }

  private func requestPermission(_ done: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission { granted in DispatchQueue.main.async { done(granted) } }
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission { granted in DispatchQueue.main.async { done(granted) } }
    }
  }

  private func start(microphoneID: String?) throws {
    if running { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredSampleRate(48000)
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true)
    if let microphoneID,
       let input = session.availableInputs?.first(where: { $0.uid == microphoneID }) {
      try session.setPreferredInput(input)
    } else {
      try session.setPreferredInput(nil)
    }

    let input = engine.inputNode
    let hardware = engine.outputNode.outputFormat(forBus: 0)
    let playFormat = KraftAudioGuard.monoFloat(sampleRate: hardware.sampleRate)
    playerFormat = playFormat
    playbackConverter = AVAudioConverter(from: geminiPcm, to: playFormat)
    if !playerAttached {
      engine.attach(player)
      playerAttached = true
    }
    engine.connect(player, to: engine.mainMixerNode, format: playFormat)
    // La cancelación de eco exige el grafo ya cableado a la frecuencia del hardware.
    // Si no está disponible (simulador, algunos accesorios) se sigue sin ella.
    do {
      try input.setVoiceProcessingEnabled(true)
    } catch {
      // Sin AEC la conversación sigue; Gemini puede oírse a sí mismo un poco.
    }

    var inputFormat = input.outputFormat(forBus: 0)
    if !inputFormat.isUsableForCapture {
      try? input.setVoiceProcessingEnabled(false)
      inputFormat = input.outputFormat(forBus: 0)
    }
    try KraftAudioGuard.check(inputFormat)
    guard let converter = AVAudioConverter(from: inputFormat, to: KraftAudioGuard.micPcm) else {
      throw NSError(domain: "KraftVoiceAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no soportado"])
    }
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      guard let self, let data = KraftAudioGuard.convertToMicPcm(buffer, converter: converter) else { return }
      DispatchQueue.main.async { self.sink?(FlutterStandardTypedData(bytes: data)) }
    }

    engine.prepare()
    try engine.start()
    player.play()
    running = true
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
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return source
    }
    if error == nil, dest.frameLength > 0 {
      player.scheduleBuffer(dest, completionHandler: nil)
    }
  }

  func stop() {
    // El tap se quita SIEMPRE: si `start` falló a mitad, el siguiente intento
    // reventaba al instalar un segundo tap. `removeTap` sobre un bus limpio no hace nada.
    engine.inputNode.removeTap(onBus: 0)
    player.stop()
    if playerAttached {
      engine.detach(player)
      playerAttached = false
    }
    if engine.isRunning { engine.stop() }
    try? engine.inputNode.setVoiceProcessingEnabled(false)
    engine.reset()
    playbackConverter = nil
    playerFormat = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    running = false
  }
}

/// Voz del sistema para las respuestas de texto del asistente.
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
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      speaker.stopSpeaking(at: .immediate)
      speaker.speak(utterance)
      result(nil)
    case "stop":
      speaker.stopSpeaking(at: .immediate)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Dictado dentro del iPad: convierte lo que se habla en texto sin mandar el audio a ningún servidor.
/// En iPadOS 26 usa SpeechAnalyzer (rápido, con resultados parciales mientras hablas); en versiones
/// anteriores, SFSpeechRecognizer con reconocimiento en el dispositivo.
final class KraftSpeech: NSObject, FlutterStreamHandler {
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
      let mode = self.mode(for: wanted)
      guard mode != "none" else {
        result(false)
        return
      }
      requestPermission(needsSpeech: mode == "legacy") { [weak self] granted in
        guard let self else { return }
        guard granted else {
          result(false)
          return
        }
        do {
          if #available(iOS 26.0, *), mode == "analyzer" {
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
    if #available(iOS 26.0, *), SpeechTranscriber.isAvailable { return "analyzer" }
    if SFSpeechRecognizer(locale: wanted)?.isAvailable == true { return "legacy" }
    return "none"
  }

  private func locale(from arguments: Any?) -> Locale {
    guard let identifier = (arguments as? [String: Any])?["locale"] as? String, !identifier.isEmpty else {
      return Locale.current
    }
    return Locale(identifier: identifier)
  }

  private func requestPermission(needsSpeech: Bool, _ done: @escaping (Bool) -> Void) {
    let microphone: (@escaping (Bool) -> Void) -> Void = { finish in
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { granted in DispatchQueue.main.async { finish(granted) } }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in DispatchQueue.main.async { finish(granted) } }
      }
    }
    microphone { granted in
      guard granted else {
        done(false)
        return
      }
      guard needsSpeech else {
        done(true)
        return
      }
      SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async { done(status == .authorized) }
      }
    }
  }

  private func prepareSession() throws {
    let audio = AVAudioSession.sharedInstance()
    try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try audio.setActive(true)
  }

  private func emit(text: String, isFinal: Bool) {
    DispatchQueue.main.async { self.sink?(["text": text, "final": isFinal]) }
  }

  private func emit(error: Error) {
    DispatchQueue.main.async {
      self.sink?(FlutterError(code: "speech", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: iPadOS 26

  @available(iOS 26.0, *)
  private func startAnalyzer(locale wanted: Locale) throws {
    if running { return }
    try prepareSession()
    running = true
    let session = KraftAnalyzerSession(
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

  // MARK: iPadOS 15 – 18

  private func startLegacy(locale wanted: Locale) throws {
    if running { return }
    guard let recognizer = SFSpeechRecognizer(locale: wanted) else {
      throw NSError(domain: "KraftSpeech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Idioma no disponible para el dictado"])
    }
    try prepareSession()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    // Sin conexión y sin mandar el audio fuera, si el idioma está descargado.
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
    if #available(iOS 26.0, *), let session = session as? KraftAnalyzerSession { session.finish() }
    session = nil
    running = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

/// La parte de iPadOS 26: el analizador de voz y el hilo de resultados parciales.
@available(iOS 26.0, *)
final class KraftAnalyzerSession {
  init(onText: @escaping (String, Bool) -> Void, onError: @escaping (Error) -> Void) {
    self.onText = onText
    self.onError = onError
  }

  private let onText: (String, Bool) -> Void
  private let onError: (Error) -> Void
  private var analyzer: SpeechAnalyzer?
  private var continuation: AsyncStream<AnalyzerInput>.Continuation?
  private var results: Task<Void, Never>?

  /// Deja el modelo listo (lo descarga la primera vez) y devuelve en qué formato hay que darle el audio.
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
    // Lo ya reconocido no cambia; lo último se va corrigiendo mientras hablas.
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
            "El micrófono no está disponible ahora mismo. Cierra otras apps que lo estén usando e inténtalo de nuevo."
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
