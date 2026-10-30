// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ru locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ru';

  static String m0(count, skipped) =>
      "Будет добавлено: ${count}, пропущено (уже есть): ${skipped}";

  static String m1(phase) => "Предыдущий этап: ${phase}";

  static String m2(reason) => "Причина завершения по данным системы: ${reason}";

  static String m3(code) =>
      "Windows отказалась запускать FlClashCore.exe (ошибка ${code}). Политики контроля приложений, такие как Smart App Control или AppLocker, блокируют неподписанные программы; разрешите FlClash в этой политике или отключите её и повторите попытку.";

  static String m4(name) =>
      "Система сообщила об аварийном завершении при запуске. Предыдущий профиль: ${name}. Автоматическая настройка пропущена; текущий выбор и файлы сохранены.";

  static String m5(url) => "Создать профиль по ссылке ${url}?";

  static String m6(count) =>
      "${Intl.plural(count, one: '${count} день назад', few: '${count} дня назад', many: '${count} дней назад', other: '${count} дня назад')}";

  static String m7(label) =>
      "Вы уверены, что хотите удалить выбранные элементы (${label})?";

  static String m8(label) => "Вы уверены, что хотите удалить «${label}»?";

  static String m9(label) => "Сведения: ${label}";

  static String m10(label) => "Поле «${label}» не может быть пустым";

  static String m11(label) => "«${label}» уже существует";

  static String m12(name) => "${name}: уже последняя версия";

  static String m13(name) => "${name}: обновлено";

  static String m14(action) =>
      "Уже используется для «${action}». При сохранении будет перенесено сюда.";

  static String m15(modifiers) =>
      "Добавьте хотя бы одну из клавиш: ${modifiers}";

  static String m16(count) =>
      "${Intl.plural(count, one: '${count} час назад', few: '${count} часа назад', many: '${count} часов назад', other: '${count} часа назад')}";

  static String m17(count) =>
      "${Intl.plural(count, one: '${count} час', few: '${count} часа', many: '${count} часов', other: '${count} часа')}";

  static String m18(target) => "${target} — недопустимая политика";

  static String m19(proxyName) => "${proxyName} — недопустимый прокси";

  static String m20(providerName) =>
      "${providerName} — недопустимый провайдер прокси";

  static String m21(ruleSet) => "${ruleSet} — недопустимый набор правил";

  static String m22(subRule) => "${subRule} — недопустимый SUB_RULE";

  static String m23(line, message) => "Строка ${line}: ${message}";

  static String m24(appName) =>
      "1. Откройте Системные настройки > Конфиденциальность и безопасность\n2. Выберите Службы геолокации\n3. Найдите и отметьте ${appName} в списке\n\nПосле настройки вернитесь в приложение и продолжайте работу. Спасибо за сотрудничество.";

  static String m25(label, max) => "«${label}» — не более ${max} символов";

  static String m26(size) => "Освобождено ${size}";

  static String m27(count) =>
      "${Intl.plural(count, one: '${count} минуту назад', few: '${count} минуты назад', many: '${count} минут назад', other: '${count} минуты назад')}";

  static String m28(count) =>
      "${Intl.plural(count, one: '${count} месяц назад', few: '${count} месяца назад', many: '${count} месяцев назад', other: '${count} месяца назад')}";

  static String m29(code) =>
      "Сервер запретил доступ (HTTP ${code}). Возможно, ссылка устарела или учётные данные неверны";

  static String m30(code) => "Сервер отклонил запрос (HTTP ${code})";

  static String m31(code) =>
      "По этому адресу ничего не найдено (HTTP ${code}). Проверьте правильность URL";

  static String m32(detail) => "Сетевой запрос не выполнен: ${detail}";

  static String m33(code) =>
      "На сервере произошла ошибка (HTTP ${code}). Повторите попытку позже";

  static String m34(label) => "Пока нет: ${label}";

  static String m35(label) => "Значение «${label}» должно быть числом";

  static String m36(message) =>
      "Ядро не может разобрать этот прокси: ${message}";

  static String m37(name) =>
      "Имя ${name} уже занято другим прокси или группой прокси";

  static String m38(path) =>
      "Группы прокси ссылаются друг на друга по кругу: ${path}";

  static String m39(names) => "Эти провайдеры прокси не существуют: ${names}";

  static String m40(names) => "Эти прокси или политики не существуют: ${names}";

  static String m41(name) =>
      "${name} — встроенное имя политики, его нельзя использовать";

  static String m42(names) =>
      "Собственные группы прокси профиля ссылаются на прокси, которых больше нет среди пользовательских: ${names}";

  static String m43(count) =>
      "Проблем: ${count}, применение переопределения может завершиться ошибкой";

  static String m44(location) =>
      "Проверьте ${location}. Заполните или исправьте поле перед просмотром.";

  static String m45(locations) =>
      "Ресурс используется в ${locations}. Измените ссылки перед удалением.";

  static String m46(label) =>
      "Значение «${label}» должно быть от 1024 до 49151";

  static String m47(label, profiles) =>
      "«${label}» всё ещё используется в пользовательских группах прокси или правилах профилей: ${profiles}. Сначала уберите его оттуда";

  static String m48(profiles, label) =>
      "В подписках профилей ${profiles} уже есть «${label}», и после переименования они будут использовать его. Выберите другое имя";

  static String m49(count) => "${count} прокси";

  static String m50(host) =>
      "Текущая конфигурация не позволяет загрузить этот объект. Разрешить этой операции прямое соединение с ${host}? Разрешение истечёт после завершения операции или изменения источника.";

  static String m51(target) => "GLOBAL (текущий выбор: ${target})";

  static String m52(count) =>
      "${Intl.plural(count, one: '${count} правило', few: '${count} правила', many: '${count} правил', other: '${count} правила')}";

  static String m53(appName) => "${appName} (Безопасный режим)";

  static String m54(count) =>
      "${Intl.plural(count, one: '${count} секунда', few: '${count} секунды', many: '${count} секунд', other: '${count} секунды')}";

  static String m55(count) => "Выбрано: ${count}";

  static String m56(time) => "Проверено в ${time}";

  static String m57(region) => "Регион по ответу: ${region}";

  static String m58(milliseconds) =>
      "Всего (включая очередь и тело): ${milliseconds} мс";

  static String m59(result) => "Устарело: ${result}";

  static String m60(hosts) => "Адресаты: ${hosts}";

  static String m61(label) => "«${label}» — только одно значение";

  static String m62(label) => "Значение «${label}» должно быть URL";

  static String m63(count) =>
      "${Intl.plural(count, one: '${count} год назад', few: '${count} года назад', many: '${count} лет назад', other: '${count} года назад')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("О программе"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Контроль доступа"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Через VPN проходят только выбранные приложения",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Выбор приложений, использующих прокси",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений отключён",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Выбранные приложения исключаются из VPN",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Настройки контроля доступа",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Аккаунт"),
    "action": MessageLookupByLibrary.simpleMessage("Действие"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage(
      "Проверить все задержки",
    ),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("Прямой режим"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage(
      "Глобальный режим",
    ),
    "actionMode": MessageLookupByLibrary.simpleMessage("Переключить режим"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("Режим правил"),
    "actionStart": MessageLookupByLibrary.simpleMessage("Старт/Стоп"),
    "actionTun": MessageLookupByLibrary.simpleMessage("TUN"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage(
      "Обновить профили",
    ),
    "actionView": MessageLookupByLibrary.simpleMessage("Показать/Скрыть"),
    "add": MessageLookupByLibrary.simpleMessage("Добавить"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("Добавить прокси"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage(
      "Добавить параметр",
    ),
    "addProfile": MessageLookupByLibrary.simpleMessage("Добавить профиль"),
    "addProxies": MessageLookupByLibrary.simpleMessage("Добавить прокси"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Добавить группу прокси",
    ),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Добавить провайдеров прокси",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Добавить правило"),
    "addSsid": MessageLookupByLibrary.simpleMessage("Добавить SSID"),
    "addWidget": MessageLookupByLibrary.simpleMessage("Добавить виджет"),
    "addedRules": MessageLookupByLibrary.simpleMessage("Добавленные правила"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Дополнительные параметры",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Адрес"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("Адрес сервера WebDAV"),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Введите корректный адрес WebDAV",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Расширенная конфигурация",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Сеть, DNS, добавленные правила и скрипты",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Согласен"),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Разрешить приложениям обходить VPN",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Разрешить LAN"),
    "answers": MessageLookupByLibrary.simpleMessage("Ответы"),
    "app": MessageLookupByLibrary.simpleMessage("Приложение"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений",
    ),
    "appIconDesign": MessageLookupByLibrary.simpleMessage(
      "Дизайн значка приложения",
    ),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Добавлять системный DNS",
    ),
    "appliedProfile": MessageLookupByLibrary.simpleMessage(
      "Активная конфигурация",
    ),
    "authentication": MessageLookupByLibrary.simpleMessage("Аутентификация"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "Требовать учётные данные для локального порта прокси, чтобы другие приложения не могли использовать его",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Не применяется, пока включена аутентификация",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("Разрешить"),
    "authorized": MessageLookupByLibrary.simpleMessage("Разрешено"),
    "auto": MessageLookupByLibrary.simpleMessage("Авто"),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Автозакрытие соединений",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически закрывать соединения после смены узла",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запускаться автоматически при старте системы",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("Автовключение"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Включаться автоматически при открытии приложения",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Автонастройка системного DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления (минуты)",
    ),
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backup": MessageLookupByLibrary.simpleMessage("Резервное копирование"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование и восстановление",
    ),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "Синхронизация данных через WebDAV или файлы",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "Резервная копия создана более новой версией приложения. Обновите приложение перед восстановлением",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage(
      "Резервная копия создана",
    ),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Основная информация"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Базовые политики"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("Массовое добавление"),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage(
      "По одному значению на строку или через запятую",
    ),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage(
      "По одной записи на строку: ключ, пробел, значение",
    ),
    "batchPreviewTip": m0,
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "Чтобы приложение работало в фоне, отключите для него оптимизацию батареи. Нажмите, чтобы перейти к настройкам.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "Из-за системных ограничений во время работы невозможно корректно получить статус оптимизации батареи",
    ),
    "behavior": MessageLookupByLibrary.simpleMessage("Поведение"),
    "bind": MessageLookupByLibrary.simpleMessage("Привязать"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage(
      "Режим чёрного списка",
    ),
    "blockConnection": MessageLookupByLibrary.simpleMessage(
      "Заблокировать соединение",
    ),
    "bootExitAnr": MessageLookupByLibrary.simpleMessage(
      "Приложение не отвечает",
    ),
    "bootExitCrash": MessageLookupByLibrary.simpleMessage("Сбой приложения"),
    "bootExitInitialization": MessageLookupByLibrary.simpleMessage(
      "Ошибка инициализации процесса",
    ),
    "bootExitNativeCrash": MessageLookupByLibrary.simpleMessage(
      "Сбой нативного кода",
    ),
    "bootPhaseBootstrap": MessageLookupByLibrary.simpleMessage(
      "Подготовка приложения",
    ),
    "bootPhaseCore": MessageLookupByLibrary.simpleMessage("Подключение к Core"),
    "bootPhaseRecovery": MessageLookupByLibrary.simpleMessage(
      "Запрос восстановления",
    ),
    "bootPhaseSetup": MessageLookupByLibrary.simpleMessage(
      "Инициализация конфигурации",
    ),
    "bootRecordDamaged": MessageLookupByLibrary.simpleMessage(
      "Запись защиты запуска повреждена. Автоматическая настройка пропущена. Пересоздать только эту запись или сохранить её и продолжить? Профили, настройки и диагностические файлы сохранятся.",
    ),
    "bootRecordKeep": MessageLookupByLibrary.simpleMessage(
      "Сохранить и продолжить",
    ),
    "bootRecordNewer": MessageLookupByLibrary.simpleMessage(
      "Запись запуска имеет более новый формат и будет сохранена. Автоматическая настройка пропущена; ручное управление доступно.",
    ),
    "bootRecordRebuild": MessageLookupByLibrary.simpleMessage(
      "Пересоздать запись запуска",
    ),
    "bootRecordUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не удалось прочитать или сохранить запись защиты запуска. Автоматическая настройка пропущена. Работающая служба и файлы сохранены; ручное управление доступно.",
    ),
    "bootRecoveryPhase": m1,
    "bootRecoveryReason": m2,
    "bootRecoveryRepeated": MessageLookupByLibrary.simpleMessage(
      "Запуск прерывался несколько раз подряд. Проверьте или выберите профиль в списке и запустите вручную.",
    ),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Исключённые домены"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Действует только при включённом системном прокси",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("Кэш"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("Алгоритм кэша"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "Кэш повреждён. Очистить его?",
    ),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("Размер кэша"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешите доступ к камере в системных настройках, чтобы сканировать QR-коды, или выберите изображение QR-кода из галереи.",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется доступ к камере",
    ),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage(
      "Камера недоступна",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Отмена"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("Снять выделение"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "Не удалось переключить прокси; восстановлен предыдущий выбор",
    ),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage(
      "Важные изменения",
    ),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("Новые функции"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("Исправления"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage(
      "Производительность",
    ),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("Откаты"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage(
      "Проверять TLS-сертификаты",
    ),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "Отклонять недоверенные сертификаты. Отключение подвергает подписки и резервные копии атаке «человек посередине»",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Проверить обновления"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "У вас уже последняя версия",
    ),
    "clearData": MessageLookupByLibrary.simpleMessage("Очистить данные"),
    "clearSearch": MessageLookupByLibrary.simpleMessage("Очистить поиск"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Экспорт в буфер обмена",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Импорт из буфера обмена",
    ),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось скопировать в буфер обмена. Возможно, выделение слишком велико",
    ),
    "close": MessageLookupByLibrary.simpleMessage("Закрыть"),
    "closeConnections": MessageLookupByLibrary.simpleMessage(
      "Закрыть соединения",
    ),
    "color": MessageLookupByLibrary.simpleMessage("Цвет"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Цветовые схемы"),
    "columns": MessageLookupByLibrary.simpleMessage("Столбцы"),
    "compatible": MessageLookupByLibrary.simpleMessage("Режим совместимости"),
    "configApplying": MessageLookupByLibrary.simpleMessage(
      "Применение конфигурации",
    ),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "В конфигурации обнаружены данные",
    ),
    "configInactive": MessageLookupByLibrary.simpleMessage(
      "Трафик не обрабатывается",
    ),
    "configLoaded": MessageLookupByLibrary.simpleMessage(
      "Загружена; трафик не обрабатывается",
    ),
    "configRetained": MessageLookupByLibrary.simpleMessage(
      "Новая конфигурация не применена; используется предыдущая",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Подтвердить"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите удалить все данные?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите удалить эту группу прокси?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите закрыть текущее окно?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите принудительно завершить ядро со сбоем?",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "После подтверждения существующие данные будут перезаписаны",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("Подключено"),
    "connecting": MessageLookupByLibrary.simpleMessage("Подключение…"),
    "connection": MessageLookupByLibrary.simpleMessage("Соединение"),
    "connections": MessageLookupByLibrary.simpleMessage("Соединения"),
    "connectivity": MessageLookupByLibrary.simpleMessage("Подключение: "),
    "content": MessageLookupByLibrary.simpleMessage("Содержимое"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Содержимое не может быть пустым",
    ),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Контентная"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Управление глобальными добавленными правилами",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Копировать"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Копировать переменные окружения",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Копировать ссылку"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Скопировано"),
    "core": MessageLookupByLibrary.simpleMessage("Ядро"),
    "coreBlockedByPolicyTip": m3,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Smart App Control в Windows заблокировал неподписанный FlClashCore.exe. Откройте Безопасность Windows → Управление приложениями и браузером → Параметры Smart App Control, выберите «Выкл.» и снова запустите FlClash. Повторно включить Smart App Control без переустановки Windows нельзя.",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Статус ядра"),
    "country": MessageLookupByLibrary.simpleMessage("Регион"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Обнаружен сбой"),
    "crashDetectedTip": m4,
    "crashTest": MessageLookupByLibrary.simpleMessage("Тест сбоя"),
    "create": MessageLookupByLibrary.simpleMessage("Создать"),
    "createProfileFromUrlTip": m5,
    "creationTime": MessageLookupByLibrary.simpleMessage("Время создания"),
    "custom": MessageLookupByLibrary.simpleMessage("Вручную"),
    "customProxiesEmpty": MessageLookupByLibrary.simpleMessage(
      "Пользовательских прокси нет, поэтому используются прокси самого профиля",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Вырезать"),
    "dark": MessageLookupByLibrary.simpleMessage("Тёмная"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Панель"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "Обнаружены изменения данных. Сохранить их?",
    ),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "Не удалось сохранить изменение; оно отменено",
    ),
    "daysAgo": m6,
    "defaultText": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "delay": MessageLookupByLibrary.simpleMessage("Задержка"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Тест задержки"),
    "delete": MessageLookupByLibrary.simpleMessage("Удалить"),
    "deleteMultipTip": m7,
    "deleteTip": m8,
    "desc": MessageLookupByLibrary.simpleMessage(
      "Многоплатформенный прокси-клиент на основе ClashMeta: простой и удобный, с открытым исходным кодом и без рекламы.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Назначение"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "GeoIP назначения",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage(
      "ASN IP назначения",
    ),
    "details": m9,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Использует сторонний API; только для справки",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Режим разработчика"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Режим разработчика включён.",
    ),
    "dialerProxy": MessageLookupByLibrary.simpleMessage(
      "Прокси для подключения",
    ),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Исход, через который идёт обращение к NTP-серверу",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Прямой"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Отключить UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("Выключено"),
    "discardChanges": MessageLookupByLibrary.simpleMessage(
      "Отменить изменения?",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Отключено"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Доступна новая версия",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("Перехват DNS"),
    "dnsMode": MessageLookupByLibrary.simpleMessage("Режим DNS"),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS-запросы"),
    "docked": MessageLookupByLibrary.simpleMessage("Закреплённая"),
    "domain": MessageLookupByLibrary.simpleMessage("Домен"),
    "download": MessageLookupByLibrary.simpleMessage("Загрузка"),
    "edit": MessageLookupByLibrary.simpleMessage("Редактировать"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Редактировать глобальные правила",
    ),
    "editProxy": MessageLookupByLibrary.simpleMessage("Редактировать прокси"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Редактировать группу прокси",
    ),
    "editRule": MessageLookupByLibrary.simpleMessage("Редактировать правило"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Изменить SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Редактор недоступен",
    ),
    "emptyTip": m10,
    "en": MessageLookupByLibrary.simpleMessage("Английский"),
    "enabled": MessageLookupByLibrary.simpleMessage("Включено"),
    "entries": MessageLookupByLibrary.simpleMessage(" записей"),
    "error": MessageLookupByLibrary.simpleMessage("Ошибка"),
    "exclude": MessageLookupByLibrary.simpleMessage("Скрыть из недавних задач"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "Скрывать приложение из недавних задач, когда оно в фоне",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage(
      "Фильтр исключения узлов",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Исключённые SSID"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "При подключении к Wi-Fi с исключённым SSID состояние работы приложения переключается автоматически",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("Исключаемые типы"),
    "existsTip": m11,
    "exit": MessageLookupByLibrary.simpleMessage("Выход"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage(
      "Выйти из полноэкранного режима",
    ),
    "expand": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Ожидаемый статус"),
    "expireTime": MessageLookupByLibrary.simpleMessage("Срок действия"),
    "exportFile": MessageLookupByLibrary.simpleMessage("Экспорт файла"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Экспорт логов"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Экспорт выполнен"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Экспрессивная"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "Внешний контроллер",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "При включении ядром Clash можно управлять через порт 9090",
    ),
    "externalLink": MessageLookupByLibrary.simpleMessage("Внешняя ссылка"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("Очень крупный"),
    "fade": MessageLookupByLibrary.simpleMessage("Растворение"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Фильтр Fake-IP"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage(
      "Режим фильтра Fake-IP",
    ),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "blacklist исключает совпадения, whitelist — только их, rule — по правилам",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Диапазон Fake-IP"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage(
      "Диапазон Fake-IP (IPv6)",
    ),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("TTL Fake-IP"),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Фильтр fallback"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Точная передача"),
    "file": MessageLookupByLibrary.simpleMessage("Файл"),
    "fileDesc": MessageLookupByLibrary.simpleMessage(
      "Загрузить файл профиля напрямую",
    ),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "Файл изменён. Сохранить изменения?",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Фильтр"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Поиск процесса"),
    "floating": MessageLookupByLibrary.simpleMessage("Плавающая"),
    "followProfile": MessageLookupByLibrary.simpleMessage("Как в профиле"),
    "followSystem": MessageLookupByLibrary.simpleMessage("Как в системе"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Шрифт"),
    "fontSize": MessageLookupByLibrary.simpleMessage("Размер"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите принудительно перезапустить ядро?",
    ),
    "format": MessageLookupByLibrary.simpleMessage("Формат"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("Фруктовый микс"),
    "general": MessageLookupByLibrary.simpleMessage("Общие"),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления",
    ),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления должен быть больше 0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Настройки Geo"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Ресурсы Geo"),
    "geoSkipped": m12,
    "geoUpdated": m13,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo: экономия памяти",
    ),
    "global": MessageLookupByLibrary.simpleMessage("Глобальный"),
    "go": MessageLookupByLibrary.simpleMessage("Перейти"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Скачать"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Перейти к настройке скрипта",
    ),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Кэшировать изменения?",
    ),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Служба Helper недоступна, поэтому TUN-режим включить нельзя. Переустановите FlClash.",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Скрыть из списка"),
    "hideIp": MessageLookupByLibrary.simpleMessage("Скрыть IP"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Скрыть пароль"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage(
      "Скрывать узлы с таймаутом",
    ),
    "hideTimeoutProxiesDesc": MessageLookupByLibrary.simpleMessage(
      "Не показывать узлы, у которых последний тест задержки завершился таймаутом",
    ),
    "host": MessageLookupByLibrary.simpleMessage("Хост"),
    "hotkeyConflictWith": m14,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "Глобальные горячие клавиши работают, даже когда окно скрыто. Нажмите на действие, чтобы записать сочетание клавиш.",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage("Горячие клавиши"),
    "hotkeyNeedsModifier": m15,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("Не задано"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не зарегистрировано: сочетание может быть занято другим приложением",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("часов"),
    "hoursAgo": m16,
    "hoursCount": m17,
    "icon": MessageLookupByLibrary.simpleMessage("Значок"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("История значков"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Стиль значков"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("С подложкой"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("Скрыто"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("Без подложки"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("URL значка"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Игнорировать оптимизацию батареи",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Импорт"),
    "importFile": MessageLookupByLibrary.simpleMessage("Импорт из файла"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("Импорт из URL"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Импорт по URL"),
    "inbound": MessageLookupByLibrary.simpleMessage("Входящие"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage(
      "Включить все прокси",
    ),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "Подключает все прокси вне групп; ниже можно добавить дополнительные группы прокси",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Включить всех провайдеров прокси",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "При включении группа берёт всех провайдеров прокси этого профиля: собственных провайдеров подписки, а также профили и прокси-провайдеры приложения, которые использует любая группа прокси",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Бессрочно"),
    "init": MessageLookupByLibrary.simpleMessage("Инициализация"),
    "initiator": MessageLookupByLibrary.simpleMessage("Инициатор"),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Введите название группы прокси",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Введите содержимое правила",
    ),
    "installedAppsPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Разрешение на список приложений отклонено, поэтому установленные приложения недоступны. Предоставьте его вручную в системных настройках.",
    ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Эта система не выдаёт список установленных приложений без разрешения. Предоставьте его, чтобы настроить прокси для отдельных приложений.",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется разрешение на список приложений",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage("Умный выбор"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("Имя интерфейса"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сетевой интерфейс для исходящих соединений",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage(
      "Исходящий интерфейс",
    ),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("Очистить"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("Вручную"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage(
      "Как в конфигурации",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Интернет"),
    "interval": MessageLookupByLibrary.simpleMessage("Интервал"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Внутренний IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Недопустимый файл резервной копии",
    ),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "Метка DSCP не может превышать 63",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "Поддерживаются только tcp и udp",
    ),
    "invalidPolicy": m18,
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "Этот QR-код не содержит ссылку на профиль",
    ),
    "invalidProxy": m19,
    "invalidProxyProvider": m20,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "Введите числа или диапазоны, например 80 или 8000-9000, через /",
    ),
    "invalidRuleSet": m21,
    "invalidSubRule": m22,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP-адрес"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipClassificationDisclosure": MessageLookupByLibrary.simpleMessage(
      "Кнопка отправляет этот IP в proxycheck.io по HTTPS для классификации. Сервис также видит выходной IP запроса, который может отличаться. Лимит без регистрации — 100 запросов в день; запрос через прокси может быть отклонён. При отказе маршрут и источник не меняются. Нет поля — неизвестно; гарантий безопасности нет. Запрос отключает необязательное сохранение положительных проверок в панели, но не все журналы сервера.",
    ),
    "ipClassificationStart": MessageLookupByLibrary.simpleMessage(
      "Классифицировать этот IP",
    ),
    "ipFlagAnonymous": MessageLookupByLibrary.simpleMessage("Анонимный сервис"),
    "ipFlagCompromised": MessageLookupByLibrary.simpleMessage(
      "Скомпрометированный узел",
    ),
    "ipFlagHosting": MessageLookupByLibrary.simpleMessage("Признак хостинга"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("Прокси"),
    "ipFlagScraper": MessageLookupByLibrary.simpleMessage(
      "Сервис сбора данных",
    ),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("Метки"),
    "ipLookupAutomatic": MessageLookupByLibrary.simpleMessage(
      "Автопроверка на панели",
    ),
    "ipLookupBodyLimit": MessageLookupByLibrary.simpleMessage(
      "Слишком большой ответ",
    ),
    "ipLookupCancelled": MessageLookupByLibrary.simpleMessage("Запрос отменён"),
    "ipLookupCheckedAt": MessageLookupByLibrary.simpleMessage(
      "Время наблюдения",
    ),
    "ipLookupDisclosure": MessageLookupByLibrary.simpleMessage(
      "Проверка выходного IP и страны через Cloudflare по HTTPS. Автопроверка работает только на открытой панели, когда приложение на переднем плане и служба запущена. Результат не описывает все сайты.",
    ),
    "ipLookupDisplayOnly": MessageLookupByLibrary.simpleMessage(
      "Скрывает только отображение. Копируется исходный IP; сетевые запросы не блокируются.",
    ),
    "ipLookupHttpFailed": MessageLookupByLibrary.simpleMessage(
      "Источник отклонил запрос",
    ),
    "ipLookupInvalid": MessageLookupByLibrary.simpleMessage(
      "Недопустимый или неполный ответ",
    ),
    "ipLookupIpMismatch": MessageLookupByLibrary.simpleMessage(
      "IP в ответе не совпадает",
    ),
    "ipLookupManual": MessageLookupByLibrary.simpleMessage(
      "Проверить выходной IP",
    ),
    "ipLookupNotChecked": MessageLookupByLibrary.simpleMessage("Не проверено"),
    "ipLookupRoutes": MessageLookupByLibrary.simpleMessage("Текущие правила"),
    "ipLookupSourceWarning": MessageLookupByLibrary.simpleMessage(
      "Предупреждение источника: результат получен, но возможны ограничения квоты или доступа.",
    ),
    "ipLookupStale": MessageLookupByLibrary.simpleMessage(
      "Предыдущее наблюдение",
    ),
    "ipLookupTlsFailed": MessageLookupByLibrary.simpleMessage(
      "Проверка сертификата не пройдена",
    ),
    "ipLookupWaiting": MessageLookupByLibrary.simpleMessage(
      "Ожидание интервала 30 секунд",
    ),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("Организация"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось определить тип IP",
    ),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("Проверить снова"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("Источник ответа"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("Источники"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage(
      "Другой исходящий IP",
    ),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("Тип не определён"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage(
      "Лимит запросов",
    ),
    "ipType": MessageLookupByLibrary.simpleMessage("Тип"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("Бизнес"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("Дата-центр"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("Домашний"),
    "ipTypeWireless": MessageLookupByLibrary.simpleMessage(
      "Беспроводной (сотовая или спутниковая связь)",
    ),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "При включении можно принимать трафик IPv6",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить входящий IPv6",
    ),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("Тайм-аут IPv6 (мс)"),
    "ja": MessageLookupByLibrary.simpleMessage("Японский"),
    "justNow": MessageLookupByLibrary.simpleMessage("Только что"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Интервал TCP keep-alive",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Ключ"),
    "language": MessageLookupByLibrary.simpleMessage("Язык"),
    "large": MessageLookupByLibrary.simpleMessage("Крупный"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("Последнее обновление"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage(
      "Запуск не завершён",
    ),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "Предыдущий запуск не завершён. Причина неизвестна. Автоматическая настройка пропущена; выбор и файлы сохранены. Можно запустить вручную.",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("Макет"),
    "light": MessageLookupByLibrary.simpleMessage("Светлая"),
    "lineIssueTip": m23,
    "lineWrap": MessageLookupByLibrary.simpleMessage("Перенос строк"),
    "list": MessageLookupByLibrary.simpleMessage("Список"),
    "listen": MessageLookupByLibrary.simpleMessage("Прослушивание"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage(
      "Метка маршрутизации",
    ),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage(
      "Только Linux",
    ),
    "liveConnections": MessageLookupByLibrary.simpleMessage(
      "Активные соединения",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Загрузка…"),
    "local": MessageLookupByLibrary.simpleMessage("Локально"),
    "localCrashReports": MessageLookupByLibrary.simpleMessage(
      "Локальные отчёты о сбоях",
    ),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "Доступ к локальной сети запрещён: используется стек gvisor, локальная сеть недоступна.",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Разрешение на геолокацию",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Разрешение на геолокацию отклонено, поэтому невозможно получить имя текущей сети Wi-Fi. Включите разрешение на геолокацию вручную в системных настройках.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "По требованию системы для получения имени сети Wi-Fi необходимо разрешение на геолокацию. На Android выберите «Разрешить всегда», иначе имя сети Wi-Fi нельзя получить, пока приложение в фоне.",
    ),
    "locationPermissionGuide": m24,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Требуется разрешение на геолокацию",
    ),
    "log": MessageLookupByLibrary.simpleMessage("Лог"),
    "logLevel": MessageLookupByLibrary.simpleMessage("Уровень логов"),
    "logcat": MessageLookupByLibrary.simpleMessage("Захват логов"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "При отключении раздел логов будет скрыт",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Логи"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Логи и диагностика",
    ),
    "logsTest": MessageLookupByLibrary.simpleMessage("Тест логов"),
    "loopback": MessageLookupByLibrary.simpleMessage(
      "Снятие ограничения loopback для UWP",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Свободный"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage(
      "Сопоставлять IP источника",
    ),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage(
      "Макс. число неудач",
    ),
    "maxLengthTip": m25,
    "maximize": MessageLookupByLibrary.simpleMessage("Развернуть"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage(
      "Резидентная память",
    ),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage(
      "Приложение и общая",
    ),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage(
      "Свободная куча",
    ),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage(
      "Используемая куча",
    ),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "Ядро не запущено",
    ),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage(
      "Накладные расходы среды",
    ),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("Стеки горутин"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "Оценка по резидентной памяти процессов; может отличаться от данных системы.",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "Ядро работает в процессе приложения. Его доля оценивается по статистике среды выполнения, остальное относится к приложению и общей памяти.",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Память"),
    "memoryReleased": MessageLookupByLibrary.simpleMessage(
      "Память освобождена",
    ),
    "memoryReleasedSize": m26,
    "messageTest": MessageLookupByLibrary.simpleMessage("Тест сообщения"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("Это сообщение."),
    "min": MessageLookupByLibrary.simpleMessage("Минимальный"),
    "minimize": MessageLookupByLibrary.simpleMessage("Свернуть"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage(
      "Сворачивать при выходе",
    ),
    "minutesAgo": m27,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Смешанный порт"),
    "mode": MessageLookupByLibrary.simpleMessage("Режим"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Монохром"),
    "monthsAgo": m28,
    "more": MessageLookupByLibrary.simpleMessage("Ещё"),
    "name": MessageLookupByLibrary.simpleMessage("Название"),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("Нижняя панель"),
    "network": MessageLookupByLibrary.simpleMessage("Сеть"),
    "networkAccessDeniedError": m29,
    "networkBadResponseError": m30,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage(
      "Запрос отменён",
    ),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "Не удалось подключиться к серверу. Проверьте подключение к сети или настройки прокси",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage("Проверка сети"),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "Не удалось определить адрес сервера. Проверьте правильность URL и работу DNS",
    ),
    "networkNotFoundError": m31,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Слишком много запросов (HTTP 429). Подождите немного и повторите попытку",
    ),
    "networkRequestFailed": m32,
    "networkServerError": m33,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Скорость сети"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "Время ожидания запроса истекло. Проверьте сеть или прокси и повторите попытку",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "Не удалось установить защищённое соединение. Сертификат сервера может быть недействителен, или соединение перехватывается",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("Тип сети"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Нейтральная"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("Следующее совпадение"),
    "no": MessageLookupByLibrary.simpleMessage("Нет"),
    "noData": MessageLookupByLibrary.simpleMessage("Нет данных"),
    "noInfo": MessageLookupByLibrary.simpleMessage("Нет информации"),
    "noNetwork": MessageLookupByLibrary.simpleMessage("Нет сети"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("Приложения без сети"),
    "noRecords": MessageLookupByLibrary.simpleMessage("Записей пока нет"),
    "noResolve": MessageLookupByLibrary.simpleMessage("Не разрешать IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "Не разрешать имя хоста",
    ),
    "noSearchResults": MessageLookupByLibrary.simpleMessage(
      "Ничего не найдено",
    ),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage(
      "Этот внешний ресурс не является текстовым файлом",
    ),
    "none": MessageLookupByLibrary.simpleMessage("Нет"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "Текущую группу прокси нельзя выбрать",
    ),
    "ntpInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал синхронизации (минуты)",
    ),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "Брать время с NTP-сервера, а не из системных часов",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Добавьте профиль, чтобы начать",
    ),
    "nullTip": m34,
    "numberTip": m35,
    "onDemand": MessageLookupByLibrary.simpleMessage("По условию"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "Настройте состояние работы приложения для определённых сценариев",
    ),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Учитывать только трафик прокси",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("Необязательно"),
    "options": MessageLookupByLibrary.simpleMessage("Опции"),
    "other": MessageLookupByLibrary.simpleMessage("Другое"),
    "otherContributors": MessageLookupByLibrary.simpleMessage(
      "Другие участники",
    ),
    "outboundIp": MessageLookupByLibrary.simpleMessage("Исходящий IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage(
      "Режим исходящего трафика",
    ),
    "override": MessageLookupByLibrary.simpleMessage("Переопределение"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Переопределить DNS"),
    "overrideEntries": MessageLookupByLibrary.simpleMessage(
      "Переопределяемые параметры",
    ),
    "overrideMode": MessageLookupByLibrary.simpleMessage(
      "Режим переопределения",
    ),
    "overrideNtp": MessageLookupByLibrary.simpleMessage("Переопределить NTP"),
    "overrideScript": MessageLookupByLibrary.simpleMessage(
      "Скрипт переопределения",
    ),
    "overwriteIssueCoreRejected": m36,
    "overwriteIssueDuplicateName": m37,
    "overwriteIssueEmptyName": MessageLookupByLibrary.simpleMessage(
      "Имя не задано",
    ),
    "overwriteIssueGroupLoop": m38,
    "overwriteIssueMissingProviders": m39,
    "overwriteIssueMissingProxies": m40,
    "overwriteIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "Не выбраны ни прокси, ни провайдеры прокси, поэтому ядро отклонит эту группу",
    ),
    "overwriteIssueReservedName": m41,
    "overwriteIssueSubscriptionGroupMissingProxies": m42,
    "overwriteIssuesSummary": m43,
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage(
      "Пользовательский",
    ),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "Пользовательский режим: полная настройка прокси, групп прокси и правил",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("Палитра"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "paste": MessageLookupByLibrary.simpleMessage("Вставить"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("Выбрать из галереи"),
    "pinWindow": MessageLookupByLibrary.simpleMessage(
      "Закрепить поверх всех окон",
    ),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Привяжите WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Введите название скрипта",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Загрузите корректный QR-код",
    ),
    "policyActualPreview": MessageLookupByLibrary.simpleMessage(
      "Фактически принятая конфигурация",
    ),
    "policyAndroidRequired": MessageLookupByLibrary.simpleMessage(
      "Применение управляемых политик пока доступно только на Android. Редактирование черновиков и просмотр остаются доступны.",
    ),
    "policyApply": MessageLookupByLibrary.simpleMessage(
      "Сохранить и запросить применение",
    ),
    "policyApplyConfirm": MessageLookupByLibrary.simpleMessage(
      "Эта политика задаёт маршрутизацию и DNS, включая явный DIRECT. Исходные правила, DNS, провайдеры и специальные переопределения не используются. Выбор управляемых узлов будет сброшен. Остановленный прокси не запускается.",
    ),
    "policyApplyRequested": MessageLookupByLibrary.simpleMessage(
      "Выбор сохранён, применение запрошено. Проверьте фактическое состояние конфигурации.",
    ),
    "policyDraftAuthentication": MessageLookupByLibrary.simpleMessage(
      "Использовать имя пользователя и пароль",
    ),
    "policyDraftBackupConsent": MessageLookupByLibrary.simpleMessage(
      "Снимок содержит черновики и может содержать учётные данные и исходные материалы. Повторно подтвердите резервное копирование перед экспортом.",
    ),
    "policyDraftBackupLocal": MessageLookupByLibrary.simpleMessage(
      "В выбранный локальный файл будет сохранён незашифрованный ZIP с полными черновиками, учётными данными и материалами миграции. Продолжить?",
    ),
    "policyDraftBackupWebDav": MessageLookupByLibrary.simpleMessage(
      "В выбранную службу WebDAV будет отправлен незашифрованный ZIP с полными черновиками, учётными данными и материалами миграции. Продолжить?",
    ),
    "policyDraftBootstrap": MessageLookupByLibrary.simpleMessage(
      "Начальный DNS (DIRECT)",
    ),
    "policyDraftConflict": MessageLookupByLibrary.simpleMessage(
      "Сохранённый черновик изменился. Ввод сохранён; загрузите актуальную версию.",
    ),
    "policyDraftCopyFull": MessageLookupByLibrary.simpleMessage(
      "Копировать полную конфигурацию",
    ),
    "policyDraftCopyFullConfirm": MessageLookupByLibrary.simpleMessage(
      "Копировать в буфер обмена полную конфигурацию, включая имена пользователей и пароли?",
    ),
    "policyDraftDeleted": MessageLookupByLibrary.simpleMessage(
      "Черновик политики удалён",
    ),
    "policyDraftDirectWarning": MessageLookupByLibrary.simpleMessage(
      "DIRECT по умолчанию отправляет DNS-запросы доменов без совпадений напрямую выбранной службе DNS.",
    ),
    "policyDraftDiscard": MessageLookupByLibrary.simpleMessage(
      "Отменить несохранённые изменения?",
    ),
    "policyDraftDnsServices": MessageLookupByLibrary.simpleMessage(
      "Службы DNS",
    ),
    "policyDraftDomainDefault": MessageLookupByLibrary.simpleMessage(
      "Политика для доменов без совпадений",
    ),
    "policyDraftDomainRules": MessageLookupByLibrary.simpleMessage(
      "Доменные правила",
    ),
    "policyDraftExtract": MessageLookupByLibrary.simpleMessage(
      "Извлечь из сохранённой конфигурации",
    ),
    "policyDraftExtractConfirm": MessageLookupByLibrary.simpleMessage(
      "Заменить содержимое редактора черновиком из локальных материалов? Скрипты не выполняются. Неподдерживаемые правила блокируют миграцию. Конфигурация не применяется.",
    ),
    "policyDraftExtractFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось извлечь локальные материалы. Черновик не изменён.",
    ),
    "policyDraftGeneratePreview": MessageLookupByLibrary.simpleMessage(
      "Просмотр сгенерированного черновика",
    ),
    "policyDraftGroups": MessageLookupByLibrary.simpleMessage(
      "Статические группы прокси",
    ),
    "policyDraftIncomplete": m44,
    "policyDraftIpDefault": MessageLookupByLibrary.simpleMessage(
      "Политика для IP без совпадений",
    ),
    "policyDraftIpRules": MessageLookupByLibrary.simpleMessage("Правила IP"),
    "policyDraftListeners": MessageLookupByLibrary.simpleMessage(
      "Порты прослушивания для просмотра",
    ),
    "policyDraftLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить черновик. Повторите загрузку.",
    ),
    "policyDraftMembers": MessageLookupByLibrary.simpleMessage(
      "Выберите фиксированные узлы",
    ),
    "policyDraftMigration": MessageLookupByLibrary.simpleMessage(
      "Исторические материалы миграции",
    ),
    "policyDraftMigrationBlocked": MessageLookupByLibrary.simpleMessage(
      "Миграция заблокирована. Исходные материалы и позиции правил сохранены. Изменение извлечённых строк или значений по умолчанию не снимает блокировку.",
    ),
    "policyDraftMigrationChoices": MessageLookupByLibrary.simpleMessage(
      "Извлечённые строки — кандидаты. Явно выберите обе политики по умолчанию, DNS и начальный DNS. Исходный профиль, переопределения и глобальный DNS используют прежний путь конфигурации. Предпросмотр не является действующей конфигурацией.",
    ),
    "policyDraftMigrationIp": MessageLookupByLibrary.simpleMessage(
      "Правила IP назначения могут ограничивать и доменные подключения; разделение не сохраняет эту защиту.",
    ),
    "policyDraftMigrationMatch": MessageLookupByLibrary.simpleMessage(
      "После MATCH есть другие правила. Его позицию нельзя заменить правилом по умолчанию в конце.",
    ),
    "policyDraftMigrationScript": MessageLookupByLibrary.simpleMessage(
      "При извлечении скрипты не выполняются; их вывод неизвестен.",
    ),
    "policyDraftMigrationUnsupported": MessageLookupByLibrary.simpleMessage(
      "Правило, ресурс или конфигурация не поддерживаются при миграции.",
    ),
    "policyDraftMissing": MessageLookupByLibrary.simpleMessage(
      "Этот профиль больше не существует. Ввод не сохранён.",
    ),
    "policyDraftMoveDown": MessageLookupByLibrary.simpleMessage("Вниз"),
    "policyDraftMoveUp": MessageLookupByLibrary.simpleMessage("Вверх"),
    "policyDraftNeedsPreview": MessageLookupByLibrary.simpleMessage(
      "Данные ещё требуют проверки при генерации предпросмотра",
    ),
    "policyDraftNodes": MessageLookupByLibrary.simpleMessage(
      "Фиксированные узлы SOCKS5",
    ),
    "policyDraftProtocol": MessageLookupByLibrary.simpleMessage("Протокол"),
    "policyDraftReadOnly": MessageLookupByLibrary.simpleMessage(
      "Неизвестная версия или неподдерживаемая структура. Исходное содержимое сохранено; изменение и просмотр недоступны.",
    ),
    "policyDraftReady": MessageLookupByLibrary.simpleMessage(
      "Предпросмотр черновика проверен; не применён",
    ),
    "policyDraftRebuild": MessageLookupByLibrary.simpleMessage(
      "Создать независимый черновик",
    ),
    "policyDraftRebuildConfirm": MessageLookupByLibrary.simpleMessage(
      "Отбросить черновик и материалы миграции? Новая политика не гарантирует сохранение защиты старой конфигурации. Исходный профиль и действующая конфигурация не изменятся.",
    ),
    "policyDraftReferenced": m45,
    "policyDraftReload": MessageLookupByLibrary.simpleMessage(
      "Загрузить сохранённый черновик",
    ),
    "policyDraftRestoreFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось завершить восстановление. Повторно загрузите данные для проверки. Уведомления о необходимости восстановления остаются в силе.",
    ),
    "policyDraftRestoreWarning": MessageLookupByLibrary.simpleMessage(
      "При перезаписи объекты заменяются, если архив содержит их данные; отсутствующие черновики могут быть удалены. Архив без объектов сохраняет существующие объекты. Продолжить?",
    ),
    "policyDraftRevealCredentials": MessageLookupByLibrary.simpleMessage(
      "Показать учётные данные",
    ),
    "policyDraftSaveFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось сохранить. Ввод и ранее сохранённый черновик сохранены.",
    ),
    "policyDraftSaved": MessageLookupByLibrary.simpleMessage(
      "Черновик сохранён; не применён",
    ),
    "policyDraftStorage": MessageLookupByLibrary.simpleMessage(
      "Черновики могут содержать учётные данные. Они хранятся в каталоге БД (в Android — в закрытом каталоге приложения). ZIP-копии не шифруются. Сохранение не применяет черновик.",
    ),
    "policyDraftTarget": MessageLookupByLibrary.simpleMessage(
      "Направление трафика",
    ),
    "policyDraftTitle": MessageLookupByLibrary.simpleMessage(
      "Черновик политики",
    ),
    "policyDraftUdp": MessageLookupByLibrary.simpleMessage(
      "Включить UDP для узла",
    ),
    "policyDraftUnsaved": MessageLookupByLibrary.simpleMessage(
      "Черновик не сохранён и не применён",
    ),
    "policyDraftUnset": MessageLookupByLibrary.simpleMessage("Не настроено"),
    "policyDraftUsername": MessageLookupByLibrary.simpleMessage(
      "Имя пользователя",
    ),
    "policyFinalPreview": MessageLookupByLibrary.simpleMessage(
      "Итоговая сформированная конфигурация",
    ),
    "policyMaintenanceNone": MessageLookupByLibrary.simpleMessage(
      "Без служебного прокси по умолчанию",
    ),
    "policyMaintenanceRequired": MessageLookupByLibrary.simpleMessage(
      "Выберите и примените служебную группу или узел либо явно выберите Auto или Direct для запроса. Прежняя цель могла исчезнуть.",
    ),
    "policyMaintenanceTarget": MessageLookupByLibrary.simpleMessage(
      "Прокси для служебных запросов",
    ),
    "policyManagedEditRequired": MessageLookupByLibrary.simpleMessage(
      "Профиль использует управляемую политику. Измените маршрутизацию и DNS в черновике и явно запросите применение.",
    ),
    "policyOriginal": MessageLookupByLibrary.simpleMessage(
      "Использовать исходный профиль",
    ),
    "policyOriginalConfirm": MessageLookupByLibrary.simpleMessage(
      "Выйти из управляемого режима и использовать исходные правила, DNS и переопределения? Путь трафика может измениться.",
    ),
    "policyOriginalStatus": MessageLookupByLibrary.simpleMessage(
      "Выбран исходный профиль",
    ),
    "policySelectedStatus": MessageLookupByLibrary.simpleMessage(
      "Политика выбрана; фактическое принятие показано отдельно",
    ),
    "policySelectionPending": MessageLookupByLibrary.simpleMessage(
      "Выбранная политика отличается от фактически принятой конфигурации.",
    ),
    "policySelectionUnavailable": MessageLookupByLibrary.simpleMessage(
      "Требуется управляемая политика, но она недоступна. Выберите допустимую политику.",
    ),
    "policyUnappliedEdits": MessageLookupByLibrary.simpleMessage(
      "Черновик отличается от выбранной политики; изменения не применены",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Порт"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Введите другой порт",
    ),
    "portTip": m46,
    "prerequisites": MessageLookupByLibrary.simpleMessage(
      "Предварительные условия",
    ),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Нажмите сочетание клавиш",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Предпросмотр"),
    "previousMatch": MessageLookupByLibrary.simpleMessage(
      "Предыдущее совпадение",
    ),
    "process": MessageLookupByLibrary.simpleMessage("Процесс"),
    "profile": MessageLookupByLibrary.simpleMessage("Профиль"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Введите положительное целое число минут. Старое некорректное значение считается одним днём.",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage("Введите интервал автообновления"),
    "profileDownloadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить подписку. Предыдущий файл сохранён.",
    ),
    "profileDownloadTimeout": MessageLookupByLibrary.simpleMessage(
      "Загрузка подписки превысила 90 секунд.",
    ),
    "profileDownloadTooLarge": MessageLookupByLibrary.simpleMessage(
      "Подписка превышает лимит загрузки 16 МиБ.",
    ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "Профиль изменён. Отключить автообновление?",
    ),
    "profileInvalidBody": MessageLookupByLibrary.simpleMessage(
      "Загруженная подписка некорректна. Предыдущий файл сохранён.",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите название профиля",
    ),
    "profileRefreshFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось обновить подписку. Проверьте состояние текущей конфигурации.",
    ),
    "profileSavedNotApplied": MessageLookupByLibrary.simpleMessage(
      "Подписка сохранена. Проверьте состояние текущей конфигурации: обновление могло ещё не примениться.",
    ),
    "profileSavedRecoveryRequired": MessageLookupByLibrary.simpleMessage(
      "Подписка сохранена, но завершение очистки не подтверждено. Перед дальнейшими запросами требуется восстановление.",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите корректный URL профиля",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Введите URL профиля",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Профили"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Сортировка профилей"),
    "project": MessageLookupByLibrary.simpleMessage("Проект"),
    "providerInUse": m47,
    "providerRenameShadowed": m48,
    "providerSourceSubscription": MessageLookupByLibrary.simpleMessage(
      "Подписка",
    ),
    "providerUrlTip": MessageLookupByLibrary.simpleMessage(
      "Поддерживаются только удалённые ресурсы",
    ),
    "providers": MessageLookupByLibrary.simpleMessage("Внешние ресурсы"),
    "proxies": MessageLookupByLibrary.simpleMessage("Прокси"),
    "proxiesCount": m49,
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("Список прокси пуст"),
    "proxyChains": MessageLookupByLibrary.simpleMessage("Цепочка прокси"),
    "proxyDefinition": MessageLookupByLibrary.simpleMessage(
      "Полная конфигурация",
    ),
    "proxyDefinitionNotMap": MessageLookupByLibrary.simpleMessage(
      "Конфигурация должна быть YAML-словарём с полями name и type",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("Фильтр узлов"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Группа прокси"),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Группа прокси пуста",
    ),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Название группы прокси уже используется",
    ),
    "proxyNode": MessageLookupByLibrary.simpleMessage("Прокси-узел"),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Провайдеры прокси"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "Список провайдеров прокси пуст",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Провайдеры прокси не могут быть пустыми",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("Тип прокси"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Очистить кэш"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("Чисто чёрный"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Чисто чёрный режим"),
    "qrImageBusy": MessageLookupByLibrary.simpleMessage(
      "Распознавание изображения занято. Используйте камеру или импортируйте URL либо файл.",
    ),
    "qrImageReadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось прочитать изображение. Выберите другое локальное изображение.",
    ),
    "qrImageTimeout": MessageLookupByLibrary.simpleMessage(
      "Время распознавания изображения истекло. Повторите позже или используйте камеру.",
    ),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR-код"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Сканируйте QR-код, чтобы получить профиль",
    ),
    "quickAdd": MessageLookupByLibrary.simpleMessage("Быстрое добавление"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("Быстрое редактирование"),
    "quickFill": MessageLookupByLibrary.simpleMessage("Быстрое заполнение"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Радуга"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("Последние запросы"),
    "recordType": MessageLookupByLibrary.simpleMessage("Тип записи"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Порт Redir"),
    "redo": MessageLookupByLibrary.simpleMessage("Повторить"),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("Освободить память"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось освободить память",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Удалённо"),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Удалённое назначение",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Убрать"),
    "replace": MessageLookupByLibrary.simpleMessage("Заменить"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("Заменить все"),
    "reportBuildIdentity": MessageLookupByLibrary.simpleMessage(
      "Данные сборки (отсутствующие поля неизвестны)",
    ),
    "reportBusy": MessageLookupByLibrary.simpleMessage(
      "Занято или истекло время ожидания. Ввод-вывод может продолжаться; обновите позже.",
    ),
    "reportCancelled": MessageLookupByLibrary.simpleMessage(
      "Отменено. Проверьте, не осталась ли неполная копия.",
    ),
    "reportCorrupt": MessageLookupByLibrary.simpleMessage(
      "Повреждённый или неподдерживаемый элемент",
    ),
    "reportDeleteAll": MessageLookupByLibrary.simpleMessage(
      "Удалить текущие отчёты",
    ),
    "reportDeleteWarning": MessageLookupByLibrary.simpleMessage(
      "Удалить выбранный отчёт или все отчёты текущего снимка? Новые отчёты могут остаться. Записи дедупликации и экспортированные копии сохраняются. Новые сбои по-прежнему будут записываться.",
    ),
    "reportDeleted": MessageLookupByLibrary.simpleMessage(
      "Выбранные отчёты удалены",
    ),
    "reportDestinationWarning": MessageLookupByLibrary.simpleMessage(
      "Проверьте место сохранения: провайдер может синхронизировать данные с облаком. Приложение не отправляет отчёт автоматически. После отмены или сбоя может остаться неполная копия.",
    ),
    "reportEmpty": MessageLookupByLibrary.simpleMessage(
      "Сохранённых отчётов нет",
    ),
    "reportExportRaw": MessageLookupByLibrary.simpleMessage(
      "Экспортировать исходный отчёт (ZIP)",
    ),
    "reportExportSummary": MessageLookupByLibrary.simpleMessage(
      "Экспортировать сводку (JSON)",
    ),
    "reportExported": MessageLookupByLibrary.simpleMessage(
      "Сохранено и проверено",
    ),
    "reportFailed": MessageLookupByLibrary.simpleMessage(
      "Операция не выполнена или выполнена частично. Обновите список и проверьте место экспорта.",
    ),
    "reportIntegrity": MessageLookupByLibrary.simpleMessage(
      "Проверка целостности не пройдена. Проверьте наличие неполной копии.",
    ),
    "reportLimited": MessageLookupByLibrary.simpleMessage(
      "Достигнут предел обработки каталога. Некоторые элементы не обработаны.",
    ),
    "reportMetadataOnly": MessageLookupByLibrary.simpleMessage(
      "Только метаданные; trace не будет дополнен автоматически",
    ),
    "reportRawMissing": MessageLookupByLibrary.simpleMessage(
      "Исходное содержимое отсутствует или не совпадает",
    ),
    "reportRawUnverified": MessageLookupByLibrary.simpleMessage(
      "Исходное содержимое не проверено",
    ),
    "reportRawWarning": MessageLookupByLibrary.simpleMessage(
      "Исходный отчёт может содержать учётные данные, адреса и фрагменты памяти. Экспортируйте только для нужного получателя. Провайдер назначения может синхронизировать данные с облаком. После отмены или сбоя может остаться неполная копия. Продолжить?",
    ),
    "reportRefresh": MessageLookupByLibrary.simpleMessage("Обновить"),
    "reportRetention": MessageLookupByLibrary.simpleMessage(
      "Лимиты: 20 отчётов, 16 МиБ, 30 дней. Автоочистка выполняется по возможности.",
    ),
    "reportStale": MessageLookupByLibrary.simpleMessage(
      "Отчёт изменился или выбор устарел. Обновите список и выберите снова.",
    ),
    "reportTruncated": MessageLookupByLibrary.simpleMessage(
      "Материалы усечены; это не полный dump",
    ),
    "reportUnknownFormat": MessageLookupByLibrary.simpleMessage(
      "Неизвестный формат отчёта",
    ),
    "reportUsage": MessageLookupByLibrary.simpleMessage(
      "Занятое место (включая неизвестные элементы и внутренний индекс)",
    ),
    "reportWrittenUnverified": MessageLookupByLibrary.simpleMessage(
      "Записано; содержимое назначения не проверено",
    ),
    "request": MessageLookupByLibrary.simpleMessage("Запрос"),
    "requestDirectRecoveryMessage": m50,
    "requestDirectRecoveryTitle": MessageLookupByLibrary.simpleMessage(
      "Восстановить через прямое соединение?",
    ),
    "requestMode": MessageLookupByLibrary.simpleMessage("Маршрут запросов"),
    "requestModeAuto": MessageLookupByLibrary.simpleMessage("Авто"),
    "requestModeDirect": MessageLookupByLibrary.simpleMessage("Напрямую"),
    "requestModeHelp": MessageLookupByLibrary.simpleMessage(
      "Для собственных запросов этого объекта. Прокси требует действующий узел; прямое соединение — доступную сеть без VPN.",
    ),
    "requestModeProxy": MessageLookupByLibrary.simpleMessage("Прокси"),
    "requestPartialCommit": MessageLookupByLibrary.simpleMessage(
      "Часть локальных изменений не удалось отменить. Файлы восстановления сохранены; автоматические обновления заблокированы.",
    ),
    "requestProxyDefault": m51,
    "requestProxyTarget": MessageLookupByLibrary.simpleMessage("Цель прокси"),
    "requestRouteUnavailable": MessageLookupByLibrary.simpleMessage(
      "Выбранный маршрут запросов недоступен.",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Запросы"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage(
      "Запросы и обновления",
    ),
    "reset": MessageLookupByLibrary.simpleMessage("Сброс"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "На этой странице есть изменения. Вы уверены, что хотите выполнить сброс?",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите выполнить сброс?",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("Ресурсы"),
    "respectRules": MessageLookupByLibrary.simpleMessage("Соблюдать правила"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS-соединения следуют правилам; требуется Proxy Server Nameserver",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("Код ответа"),
    "restart": MessageLookupByLibrary.simpleMessage("Перезапустить"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите перезапустить ядро?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Восстановить"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage(
      "Восстановить все данные",
    ),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Восстановить только профили",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия восстановления",
    ),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage(
      "Совместимость",
    ),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage(
      "Перезапись",
    ),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage(
      "Восстановление выполнено",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Повторить"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Адреса маршрутов"),
    "routeMode": MessageLookupByLibrary.simpleMessage("Режим маршрутизации"),
    "routeModeBypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Обходить частные адреса",
    ),
    "routeModeConfig": MessageLookupByLibrary.simpleMessage(
      "Использовать конфигурацию",
    ),
    "ru": MessageLookupByLibrary.simpleMessage("Русский"),
    "rule": MessageLookupByLibrary.simpleMessage("Правило"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить полный домен",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ключевое слово в домене",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению домена",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить суффикс домена",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставление по маске; поддерживаются только * и ?",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить метку DSCP (только для входящих tproxy UDP)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов назначения",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны IP-адреса",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить домены из Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя входящего подключения",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящий порт",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить тип входящего подключения",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя пользователя входящего подключения; несколько имён разделяются /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN, которой принадлежит IP",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов; IP-CIDR6 — просто псевдоним",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон суффиксов IP",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставляет все запросы, условия не нужны",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить TCP или UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило OR",
    ),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по имени процесса; на Android соответствует имени пакета",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению имени процесса; на Android соответствует имени пакета",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по маске имени процесса; поддерживаются только * и ?",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по полному пути процесса",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению пути процесса",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по маске пути процесса; поддерживаются только * и ?",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить имя повторного сопоставления; несколько имён разделяются /",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Ссылка на набор правил; требуется настроить rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны IP источника",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN IP источника",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов источника",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон суффиксов IP источника",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов источника",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Переход к подправилу; обратите внимание на скобки",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Правило пусто"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Название правила"),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BitTorrent напрямую",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "Блокировать DNS over TLS",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage(
      "Блокировать QUIC",
    ),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage(
      "Блокировать STUN",
    ),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage(
      "Локальная сеть напрямую",
    ),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple и Microsoft напрямую",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Провайдеры правил"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Набор правил"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Цель правила"),
    "rules": MessageLookupByLibrary.simpleMessage("Правила"),
    "rulesCount": m52,
    "runTime": MessageLookupByLibrary.simpleMessage("Время работы"),
    "safeMode": MessageLookupByLibrary.simpleMessage("Безопасный режим"),
    "safeModeAppTitle": m53,
    "save": MessageLookupByLibrary.simpleMessage("Сохранить"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Сохранить изменения?"),
    "script": MessageLookupByLibrary.simpleMessage("Скрипт"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Режим скрипта: использует внешние скрипты-расширения для переопределения конфигурации в один клик",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage(
      "Прокрутить к выбранному",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Поиск"),
    "seconds": MessageLookupByLibrary.simpleMessage("секунд"),
    "secondsCount": m54,
    "selectAll": MessageLookupByLibrary.simpleMessage("Выбрать всё"),
    "selectProxies": MessageLookupByLibrary.simpleMessage("Выбрать прокси"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Выбрать провайдеров прокси",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Выберите набор правил",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Выберите стратегию распределения",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage(
      "Выберите подправило",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("Выбрано"),
    "selectedCountTitle": m55,
    "server": MessageLookupByLibrary.simpleMessage("Сервер"),
    "serviceAdvanced": MessageLookupByLibrary.simpleMessage(
      "Проверка региона и сервиса",
    ),
    "serviceAdvancedExplanation": MessageLookupByLibrary.simpleMessage(
      "Необязательная разовая проверка региона и страницы сервиса анонимными запросами. Возможны обращения к дополнительным адресатам ниже. Cookie входа и данные подписки не передаются. Результат не подтверждает права аккаунта, воспроизведение или защиту всего устройства. Базовый ответ оценивается отдельно.",
    ),
    "serviceAdvancedTiming": MessageLookupByLibrary.simpleMessage(
      "Срок результата — 5 минут, интервал — не менее 30 секунд. Без автоповторов; выход со страницы отменяет незавершённую проверку. Время шага измеряется до заголовков, это не ping и не скорость.",
    ),
    "serviceAllDisabled": MessageLookupByLibrary.simpleMessage(
      "Все сервисы отключены · Управление",
    ),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("Доступен"),
    "serviceBasic": MessageLookupByLibrary.simpleMessage("Базовый ответ HTTPS"),
    "serviceBasicExplanation": MessageLookupByLibrary.simpleMessage(
      "Отображаемый сервис проверяется автоматически на переднем плане. Результат устаревает через 5 минут; смена маршрута или возврат в приложение может вызвать проверку. Интервал не менее 30 секунд. Общая проверка охватывает только включённые сервисы. Читаются лишь заголовки, без переходов и ресурсов страницы. Ответ не подтверждает функции сайта, права аккаунта или защиту всего устройства.",
    ),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("Заблокировано"),
    "serviceBodyComplete": MessageLookupByLibrary.simpleMessage(
      "Ответ прочитан полностью",
    ),
    "serviceBodyLimit": MessageLookupByLibrary.simpleMessage(
      "Достигнут предел ответа",
    ),
    "serviceCheck": MessageLookupByLibrary.simpleMessage("Проверить"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("Проверить все"),
    "serviceCheckedAt": m56,
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("Скоро появится"),
    "serviceConnectFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось получить ответ на запрос",
    ),
    "serviceDetectedRegion": m57,
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage(
      "Недопустимый провайдер",
    ),
    "serviceDisneyExplanation": MessageLookupByLibrary.simpleMessage(
      "При запуске регистрируется анонимное устройство браузера, получается временный токен и запрашивается сеанс. Токены используются только в этой проверке и не сохраняются.",
    ),
    "serviceDnsFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось разрешить имя для запроса",
    ),
    "serviceElapsed": m58,
    "serviceExpired": m59,
    "serviceFailed": MessageLookupByLibrary.simpleMessage(
      "Невозможно определить",
    ),
    "serviceHeaders": MessageLookupByLibrary.simpleMessage(
      "Заголовки получены",
    ),
    "serviceHttpResponse": MessageLookupByLibrary.simpleMessage("Ответ HTTP"),
    "serviceIndeterminate": MessageLookupByLibrary.simpleMessage(
      "Невозможно определить: проверка не завершена или формат ответа изменился.",
    ),
    "serviceManage": MessageLookupByLibrary.simpleMessage(
      "Управление сервисами",
    ),
    "serviceMarkerFound": MessageLookupByLibrary.simpleMessage(
      "Нужный маркер найден",
    ),
    "serviceMultipleRoutes": MessageLookupByLibrary.simpleMessage(
      "Разные выходы · см. запросы",
    ),
    "serviceObserved": MessageLookupByLibrary.simpleMessage(
      "Получены сведения о сервисе",
    ),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage(
      "Только оригиналы",
    ),
    "servicePending": MessageLookupByLibrary.simpleMessage("Не проверено"),
    "serviceQueued": MessageLookupByLibrary.simpleMessage(
      "Ожидание интервала проверки",
    ),
    "serviceReadError": MessageLookupByLibrary.simpleMessage(
      "Ответ прерван или не читается",
    ),
    "serviceRecipientBlocked": MessageLookupByLibrary.simpleMessage(
      "Адресат или переход вне проверки",
    ),
    "serviceRecipients": m60,
    "serviceRedirected": MessageLookupByLibrary.simpleMessage(
      "Перенаправление (не выполнено)",
    ),
    "serviceRequestLimit": MessageLookupByLibrary.simpleMessage(
      "Достигнут предел запросов",
    ),
    "serviceResponded": MessageLookupByLibrary.simpleMessage("Ответ получен"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage(
      "Доступ ограничен",
    ),
    "serviceRouteChanged": MessageLookupByLibrary.simpleMessage(
      "Маршрут изменён · повторите вручную",
    ),
    "serviceStartAdvanced": MessageLookupByLibrary.simpleMessage(
      "Запустить разовую проверку",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Состояние сервисов"),
    "serviceTlsFailed": MessageLookupByLibrary.simpleMessage(
      "Проверка TLS для запроса не пройдена",
    ),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage(
      "Нет корректного ответа на запрос",
    ),
    "serviceUnknownRoute": MessageLookupByLibrary.simpleMessage(
      "Маршрут неизвестен",
    ),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage(
      "Регион не поддерживается",
    ),
    "settings": MessageLookupByLibrary.simpleMessage("Настройки"),
    "show": MessageLookupByLibrary.simpleMessage("Показать"),
    "showLess": MessageLookupByLibrary.simpleMessage("Свернуть"),
    "showMore": MessageLookupByLibrary.simpleMessage("Развернуть"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "Кнопка остановки в уведомлении",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("Показать пароль"),
    "shrink": MessageLookupByLibrary.simpleMessage("Компактный"),
    "sidebarBlur": MessageLookupByLibrary.simpleMessage(
      "Размытие боковой панели",
    ),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage(
      "Показывать сквозь боковую панель размытый рабочий стол за окном",
    ),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Тихий запуск"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запускаться без показа окна",
    ),
    "singleAdd": MessageLookupByLibrary.simpleMessage("По одному"),
    "singleValueTip": m61,
    "size": MessageLookupByLibrary.simpleMessage("Размер"),
    "slide": MessageLookupByLibrary.simpleMessage("Сдвиг"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Порт SOCKS"),
    "sort": MessageLookupByLibrary.simpleMessage("Сортировка"),
    "source": MessageLookupByLibrary.simpleMessage("Источник"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("IP источника"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Специальный прокси"),
    "specialRules": MessageLookupByLibrary.simpleMessage("Специальные правила"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage(
      "Статистика скорости",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия распределения",
    ),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Стратегия распределения не может быть пустой",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("Список SSID пуст"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Режим стека"),
    "standard": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Стандартный режим: переопределяет базовую конфигурацию и позволяет просто добавлять правила",
    ),
    "start": MessageLookupByLibrary.simpleMessage("Старт"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage("С нуля"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Запуск VPN…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage(
      "Запуск и фоновая работа",
    ),
    "status": MessageLookupByLibrary.simpleMessage("Статус"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "При отключении используется системный DNS",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Стоп"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Остановка VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("Стратегия"),
    "style": MessageLookupByLibrary.simpleMessage("Стиль"),
    "subRule": MessageLookupByLibrary.simpleMessage("Подправило"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("Подправило пусто"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Подправило не может быть пустым",
    ),
    "submit": MessageLookupByLibrary.simpleMessage("Отправить"),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage(
      "Информация о подписке",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("Приостановлено…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("Сменить профиль"),
    "sync": MessageLookupByLibrary.simpleMessage("Синхронизация"),
    "system": MessageLookupByLibrary.simpleMessage("Система"),
    "systemApp": MessageLookupByLibrary.simpleMessage("Системные приложения"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "tab": MessageLookupByLibrary.simpleMessage("Вкладки"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Анимация вкладок"),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage(
      "Нажмите, чтобы разрешить",
    ),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("Параллельный TCP"),
    "testInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал тестирования",
    ),
    "testUrl": MessageLookupByLibrary.simpleMessage("URL для теста"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage(
      "Тестировать при использовании",
    ),
    "textScale": MessageLookupByLibrary.simpleMessage("Масштаб текста"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage(
      "Так будет выглядеть текст в приложении",
    ),
    "theme": MessageLookupByLibrary.simpleMessage("Тема"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Цвет темы"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Тёмный режим и настройка цветов",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Режим темы"),
    "tight": MessageLookupByLibrary.simpleMessage("Плотный"),
    "time": MessageLookupByLibrary.simpleMessage("Время"),
    "timeout": MessageLookupByLibrary.simpleMessage("Тайм-аут"),
    "tip": MessageLookupByLibrary.simpleMessage("Подсказка"),
    "toggle": MessageLookupByLibrary.simpleMessage("Переключить"),
    "tolerance": MessageLookupByLibrary.simpleMessage("Допуск"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("Тональный акцент"),
    "tools": MessageLookupByLibrary.simpleMessage("Инструменты"),
    "torch": MessageLookupByLibrary.simpleMessage("Фонарик"),
    "total": MessageLookupByLibrary.simpleMessage("Всего"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("Общий трафик"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Порт TProxy"),
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Статистика трафика"),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "Работает только в режиме администратора",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Выключить"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Включить"),
    "undo": MessageLookupByLibrary.simpleMessage("Отменить"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Единая задержка"),
    "unknown": MessageLookupByLibrary.simpleMessage("Неизвестно"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Неизвестная сетевая ошибка",
    ),
    "unmaximize": MessageLookupByLibrary.simpleMessage("Свернуть в окно"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Без названия"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("Открепить окно"),
    "update": MessageLookupByLibrary.simpleMessage("Обновить"),
    "upload": MessageLookupByLibrary.simpleMessage("Отдача"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage("Получить профиль по URL"),
    "urlTip": m62,
    "useHosts": MessageLookupByLibrary.simpleMessage("Использовать hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage(
      "Использовать системный hosts",
    ),
    "usedTraffic": MessageLookupByLibrary.simpleMessage(
      "Использованный трафик",
    ),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "value": MessageLookupByLibrary.simpleMessage("Значение"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Яркая"),
    "view": MessageLookupByLibrary.simpleMessage("Просмотр"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "Обнаружено изменение настроек VPN",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически направляет весь системный трафик через VpnService",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Изменения вступят в силу после перезапуска VPN",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "Настройка WebDAV",
    ),
    "whitelistMode": MessageLookupByLibrary.simpleMessage(
      "Режим белого списка",
    ),
    "writeToSystem": MessageLookupByLibrary.simpleMessage(
      "Записывать в систему",
    ),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "Также устанавливать системные часы; Android это игнорирует",
    ),
    "yearsAgo": m63,
    "yes": MessageLookupByLibrary.simpleMessage("Да"),
    "zhCN": MessageLookupByLibrary.simpleMessage("Упрощённый китайский"),
  };
}
