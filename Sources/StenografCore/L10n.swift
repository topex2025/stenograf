import Foundation

/// Язык интерфейса приложения: русский / английский / испанский.
/// Определяется по языку системы; приоритет — ru, затем es, иначе en.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ru, en, es
}

public enum L10n {
    /// Текущий язык (меняется на старте приложения, до первого рендера).
    public nonisolated(unsafe) private(set) static var language: AppLanguage = detectSystem()

    public static func detectSystem() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ru") { return .ru }
        if preferred.hasPrefix("es") { return .es }
        return .en
    }

    public static func setLanguage(_ lang: AppLanguage) { language = lang }

    public enum Key: String, CaseIterable {
        case tagline, recordStart, stopRecord, recordingMsg
        case chatgptActive, chatgptNeedsLogin, loginButton
        case searchPlaceholder, noResultsFmt, searchHint
        case emptyTitle, emptyBody, openFolder, footerFmt
        case transcriptTitle, protocolTitle, copyAll, copy, done, noProtocol
        case summaryButton, protocolButton, transcribeButton, summaryTitle
        case listenButton, pauseButton, listenTitle
        case askButton, askTitle, listening, recognizing, thinking, askPlaceholder, answerTitle, sourcesFmt
        case secondsShort, autoTranscribing, autoDoneFmt, autoFailedFmt
        case recordStopped, quit, meetingsTitle, brainSuffixLocal
    }

    static var table: [AppLanguage: [Key: String]] { [
        .ru: [
            .tagline: "память переговоров — всё локально",
            .recordStart: "⏺ Записать встречу",
            .stopRecord: "⏹ Остановить",
            .recordingMsg: "Пишу… после остановки сам сделаю транскрипт и протокол.",
            .chatgptActive: "ChatGPT: подписка активна",
            .chatgptNeedsLogin: "ChatGPT: нужен вход",
            .loginButton: "Войти в ChatGPT (подписка)",
            .searchPlaceholder: "Поиск по встречам: «смета», «Иванов обещал»…",
            .noResultsFmt: "По «%@» ничего нет",
            .searchHint: "Ищу по транскриптам и протоколам всех встреч",
            .emptyTitle: "Встреч пока нет",
            .emptyBody: "Нажми «Записать встречу» — всё остальное Стенограф сделает сам",
            .openFolder: "Открыть папку встреч",
            .footerFmt: "Мозг по умолчанию: %@ · транскрипция локально · резюме через подписку",
            .transcriptTitle: "ТРАНСКРИПТ",
            .protocolTitle: "ПРОТОКОЛ ВСТРЕЧИ",
            .copyAll: "Скопировать всё",
            .copy: "Копировать",
            .done: "Готово",
            .noProtocol: "Протокола ещё нет — нажми «Протокол» в списке",
            .summaryButton: "Выжимка",
            .protocolButton: "Протокол",
            .transcribeButton: "Транскрибировать",
            .summaryTitle: "ВЫЖИМКА",
            .listenButton: "Прослушать",
            .pauseButton: "Пауза",
            .listenTitle: "ЗАПИСЬ",
            .askButton: "Спросить",
            .askTitle: "ВОПРОС ПО ВСТРЕЧАМ",
            .listening: "Слушаю… говори вопрос, потом нажми стоп",
            .recognizing: "Распознаю вопрос…",
            .thinking: "Ищу по встречам и думаю…",
            .askPlaceholder: "Или напечатай вопрос: «о чём договорились с подрядчиком?»",
            .answerTitle: "ОТВЕТ",
            .sourcesFmt: "Нашёл в: %@",
            .secondsShort: "сек",
            .autoTranscribing: "Автопротокол: транскрибирую локально (язык: авто)…",
            .autoDoneFmt: "Готово%@: транскрипт %d знаков, протокол сохранён",
            .autoFailedFmt: "Автопротокол споткнулся: %@ — транскрибируй кнопкой",
            .recordStopped: "Запись остановлена (%d сек). Транскрибируй кнопкой в списке.",
            .quit: "Выйти",
            .meetingsTitle: "Встречи",
            .brainSuffixLocal: "резюме через подписку",
        ],
        .en: [
            .tagline: "meeting memory — all local",
            .recordStart: "⏺ Record meeting",
            .stopRecord: "⏹ Stop",
            .recordingMsg: "Recording… transcript and protocol will follow automatically.",
            .chatgptActive: "ChatGPT: subscription active",
            .chatgptNeedsLogin: "ChatGPT: sign-in needed",
            .loginButton: "Sign in with ChatGPT (subscription)",
            .searchPlaceholder: "Search meetings: “quote”, “John promised”…",
            .noResultsFmt: "Nothing found for “%@”",
            .searchHint: "Searching transcripts and protocols of all meetings",
            .emptyTitle: "No meetings yet",
            .emptyBody: "Hit “Record meeting” — Stenograf does the rest",
            .openFolder: "Open meetings folder",
            .footerFmt: "Default brain: %@ · local transcription · summaries via subscription",
            .transcriptTitle: "TRANSCRIPT",
            .protocolTitle: "MEETING PROTOCOL",
            .copyAll: "Copy all",
            .copy: "Copy",
            .done: "Done",
            .noProtocol: "No protocol yet — hit “Protocol” in the list",
            .summaryButton: "Summary",
            .protocolButton: "Protocol",
            .transcribeButton: "Transcribe",
            .summaryTitle: "SUMMARY",
            .listenButton: "Play",
            .pauseButton: "Pause",
            .listenTitle: "RECORDING",
            .askButton: "Ask",
            .askTitle: "ASK YOUR MEETINGS",
            .listening: "Listening… speak your question, then hit stop",
            .recognizing: "Recognizing the question…",
            .thinking: "Searching meetings and thinking…",
            .askPlaceholder: "Or type it: “what did we agree with the contractor?”",
            .answerTitle: "ANSWER",
            .sourcesFmt: "Found in: %@",
            .secondsShort: "s",
            .autoTranscribing: "Auto-protocol: transcribing locally (language: auto)…",
            .autoDoneFmt: "Done%@: transcript %d chars, protocol saved",
            .autoFailedFmt: "Auto-protocol failed: %@ — use the button in the list",
            .recordStopped: "Recording stopped (%d s). Transcribe with the button in the list.",
            .quit: "Quit",
            .meetingsTitle: "Meetings",
            .brainSuffixLocal: "summaries via subscription",
        ],
        .es: [
            .tagline: "memoria de reuniones — todo local",
            .recordStart: "⏺ Grabar reunión",
            .stopRecord: "⏹ Detener",
            .recordingMsg: "Grabando… la transcripción y el acta se harán solas.",
            .chatgptActive: "ChatGPT: suscripción activa",
            .chatgptNeedsLogin: "ChatGPT: hace falta entrar",
            .loginButton: "Entrar con ChatGPT (suscripción)",
            .searchPlaceholder: "Buscar en reuniones: “presupuesto”, “Juan prometió”…",
            .noResultsFmt: "Nada encontrado para «%@»",
            .searchHint: "Busco en transcripciones y actas de todas las reuniones",
            .emptyTitle: "Aún no hay reuniones",
            .emptyBody: "Pulsa «Grabar reunión» — Stenograf hace el resto",
            .openFolder: "Abrir carpeta de reuniones",
            .footerFmt: "Cerebro por defecto: %@ · transcripción local · resúmenes por suscripción",
            .transcriptTitle: "TRANSCRIPCIÓN",
            .protocolTitle: "ACTA DE REUNIÓN",
            .copyAll: "Copiar todo",
            .copy: "Copiar",
            .done: "Listo",
            .noProtocol: "Aún no hay acta — pulsa «Acta» en la lista",
            .summaryButton: "Resumen",
            .protocolButton: "Acta",
            .transcribeButton: "Transcribir",
            .summaryTitle: "RESUMEN",
            .listenButton: "Escuchar",
            .pauseButton: "Pausa",
            .listenTitle: "GRABACIÓN",
            .askButton: "Preguntar",
            .askTitle: "PREGUNTA A TUS REUNIONES",
            .listening: "Escuchando… di tu pregunta y pulsa detener",
            .recognizing: "Reconociendo la pregunta…",
            .thinking: "Buscando en reuniones y pensando…",
            .askPlaceholder: "O escríbela: «¿qué acordamos con el proveedor?»",
            .answerTitle: "RESPUESTA",
            .sourcesFmt: "Encontrado en: %@",
            .secondsShort: "s",
            .autoTranscribing: "Auto-acta: transcribiendo localmente (idioma: auto)…",
            .autoDoneFmt: "Listo%@: transcripción %d caracteres, acta guardada",
            .autoFailedFmt: "El auto-acta falló: %@ — usa el botón en la lista",
            .recordStopped: "Grabación detenida (%d s). Transcribe con el botón de la lista.",
            .quit: "Salir",
            .meetingsTitle: "Reuniones",
            .brainSuffixLocal: "resúmenes por suscripción",
        ],
    ] }

    public static func t(_ key: Key) -> String {
        table[language]?[key] ?? table[.en]?[key] ?? key.rawValue
    }

    public static func tf(_ key: Key, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
