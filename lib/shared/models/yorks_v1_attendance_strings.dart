/// Workforce attendance V2 copy (English, Arabic, Urdu, Hindi).
///
/// Placeholders in braces — `{date}`, `{name}` — are filled with
/// [AttendanceStrings.fill].
library;

import 'app_language.dart';
import 'app_strings.dart';

typedef _T = TranslatableString;

abstract final class AttendanceStrings {
  static String fill(String text, Map<String, Object?> values) {
    var result = text;
    values.forEach((key, value) {
      result = result.replaceAll('{$key}', '${value ?? ''}');
    });
    return result;
  }

  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => v == null ? value.active(language) : fill(value.active(language), v);

  // ─── Navigation ────────────────────────────────────────────────────────────
  static const overview = _T(
    en: 'Workforce Overview',
    ar: 'نظرة عامة على القوى العاملة',
    ur: 'افرادی قوت کا جائزہ',
    hi: 'कार्यबल अवलोकन',
  );
  static const overviewShort = _T(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const takeAttendance = _T(
    en: 'Take attendance',
    ar: 'تسجيل الحضور',
    ur: 'حاضری لگائیں',
    hi: 'उपस्थिति दर्ज करें',
  );
  static const attendanceShort = _T(
    en: 'Attendance',
    ar: 'الحضور',
    ur: 'حاضری',
    hi: 'उपस्थिति',
  );
  static const monthConfirmation = _T(
    en: 'Month confirmation',
    ar: 'تأكيد الشهر',
    ur: 'مہینے کی تصدیق',
    hi: 'माह की पुष्टि',
  );
  static const confirmShort = _T(
    en: 'Confirm',
    ar: 'تأكيد',
    ur: 'تصدیق',
    hi: 'पुष्टि',
  );
  static const monthlySheets = _T(
    en: 'Monthly sheets',
    ar: 'الكشوف الشهرية',
    ur: 'ماہانہ شیٹس',
    hi: 'मासिक शीट',
  );
  static const sheetsShort = _T(
    en: 'Sheets',
    ar: 'الكشوف',
    ur: 'شیٹس',
    hi: 'शीट',
  );
  static const crews = _T(en: 'Crews', ar: 'الطواقم', ur: 'عملے', hi: 'दल');
  static const readOnly = _T(
    en: 'Read only',
    ar: 'للعرض فقط',
    ur: 'صرف دیکھنے کے لیے',
    hi: 'केवल देखने के लिए',
  );

  // ─── Statuses ──────────────────────────────────────────────────────────────
  static const present = _T(
    en: 'Present',
    ar: 'حاضر',
    ur: 'حاضر',
    hi: 'उपस्थित',
  );
  static const absent = _T(
    en: 'Absent',
    ar: 'غائب',
    ur: 'غیر حاضر',
    hi: 'अनुपस्थित',
  );
  static const restDay = _T(
    en: 'Rest day',
    ar: 'يوم راحة',
    ur: 'چھٹی کا دن',
    hi: 'विश्राम दिवस',
  );
  static const annualLeave = _T(
    en: 'Annual leave',
    ar: 'إجازة سنوية',
    ur: 'سالانہ چھٹی',
    hi: 'वार्षिक अवकाश',
  );
  static const sickLeave = _T(
    en: 'Sick leave',
    ar: 'إجازة مرضية',
    ur: 'بیماری کی چھٹی',
    hi: 'बीमारी अवकाश',
  );
  static const officialLeave = _T(
    en: 'Official leave',
    ar: 'إجازة رسمية',
    ur: 'سرکاری چھٹی',
    hi: 'आधिकारिक अवकाश',
  );
  static const unpaidLeave = _T(
    en: 'Unpaid leave',
    ar: 'إجازة بدون راتب',
    ur: 'بلا تنخواہ چھٹی',
    hi: 'अवैतनिक अवकाश',
  );
  static const notMarked = _T(
    en: 'Not marked',
    ar: 'غير محدد',
    ur: 'درج نہیں',
    hi: 'अचिह्नित',
  );
  static const timeMissing = _T(
    en: 'Time missing',
    ar: 'الوقت ناقص',
    ur: 'وقت درج نہیں',
    hi: 'समय अधूरा',
  );
  static const pillPresent = _T(en: 'P', ar: 'ح', ur: 'ح', hi: 'उ');
  static const pillAbsent = _T(en: 'A', ar: 'غ', ur: 'غ', hi: 'अ');
  static const pillOff = _T(en: 'Off', ar: 'راحة', ur: 'چھٹی', hi: 'छुट्टी');
  static const pillLeave = _T(en: 'L', ar: 'إ', ur: 'چ', hi: 'अव');

  // Day states.
  static const dayEntered = _T(
    en: 'Entered',
    ar: 'مُدخل',
    ur: 'درج',
    hi: 'दर्ज',
  );
  static const dayQuestion = _T(
    en: 'Question open',
    ar: 'سؤال مفتوح',
    ur: 'سوال کھلا ہے',
    hi: 'प्रश्न खुला है',
  );
  static const dayNone = _T(
    en: 'Not entered',
    ar: 'غير مُدخل',
    ur: 'درج نہیں',
    hi: 'दर्ज नहीं',
  );
  static const dayLocked = _T(
    en: 'Month confirmed',
    ar: 'الشهر مؤكد',
    ur: 'مہینہ تصدیق شدہ',
    hi: 'माह पुष्ट',
  );

  // Month states.
  static const monthNotNeeded = _T(
    en: 'No confirmation needed',
    ar: 'لا يلزم تأكيد',
    ur: 'تصدیق کی ضرورت نہیں',
    hi: 'पुष्टि आवश्यक नहीं',
  );
  static const monthConfirmedBy = _T(
    en: 'Confirmed by {name}',
    ar: 'أكده {name}',
    ur: '{name} نے تصدیق کی',
    hi: '{name} द्वारा पुष्ट',
  );
  static const monthReady = _T(
    en: 'Ready to confirm',
    ar: 'جاهز للتأكيد',
    ur: 'تصدیق کے لیے تیار',
    hi: 'पुष्टि के लिए तैयार',
  );
  static const monthRecording = _T(
    en: 'Recording · confirm on {date}',
    ar: 'قيد التسجيل · التأكيد في {date}',
    ur: 'اندراج جاری · تصدیق {date} کو',
    hi: 'दर्ज हो रहा है · पुष्टि {date} को',
  );

  // ─── Overview ──────────────────────────────────────────────────────────────
  static const overviewReadOnlyIntro = _T(
    en: 'Every crew’s attendance as it is entered. Months confirmed by the reviewer are final; until then figures can still change.',
    ar: 'حضور كل طاقم فور إدخاله. الأشهر التي أكدها المراجع نهائية؛ وحتى ذلك الحين قد تتغير الأرقام.',
    ur: 'ہر عملے کی حاضری جیسے ہی درج ہو۔ جائزہ لینے والے کے تصدیق شدہ مہینے حتمی ہیں؛ اس سے پہلے اعداد بدل سکتے ہیں۔',
    hi: 'हर दल की उपस्थिति, जैसे ही दर्ज हो। समीक्षक द्वारा पुष्ट माह अंतिम हैं; तब तक आंकड़े बदल सकते हैं।',
  );
  static const overviewIntro = _T(
    en: 'Your crews this month. Select a crew to open its days.',
    ar: 'طواقمك هذا الشهر. اختر طاقمًا لفتح أيامه.',
    ur: 'اس مہینے آپ کے عملے۔ دن کھولنے کے لیے عملہ منتخب کریں۔',
    hi: 'इस माह आपके दल। दिन खोलने के लिए दल चुनें।',
  );
  static const kpiToday = _T(
    en: 'Today · {date}',
    ar: 'اليوم · {date}',
    ur: 'آج · {date}',
    hi: 'आज · {date}',
  );
  static const kpiCrewsOf = _T(
    en: '{a} of {b} crews',
    ar: '{a} من {b} طواقم',
    ur: '{b} میں سے {a} عملے',
    hi: '{b} में से {a} दल',
  );
  static const kpiNotYet = _T(
    en: '{n} not entered yet',
    ar: '{n} لم يُدخل بعد',
    ur: '{n} ابھی درج نہیں',
    hi: '{n} अभी दर्ज नहीं',
  );
  static const kpiAllEntered = _T(
    en: 'All crews entered',
    ar: 'تم إدخال كل الطواقم',
    ur: 'تمام عملے درج',
    hi: 'सभी दल दर्ज',
  );
  static const kpiEarlierMissing = _T(
    en: 'Earlier days not entered',
    ar: 'أيام سابقة غير مُدخلة',
    ur: 'پچھلے دن جو درج نہیں',
    hi: 'पिछले दिन जो दर्ज नहीं',
  );
  static const kpiNothingMissing = _T(
    en: 'Nothing missing',
    ar: 'لا شيء ناقص',
    ur: 'کچھ باقی نہیں',
    hi: 'कुछ बाकी नहीं',
  );
  static const kpiOvertime = _T(
    en: 'Overtime this month',
    ar: 'العمل الإضافي هذا الشهر',
    ur: 'اس مہینے کا اوور ٹائم',
    hi: 'इस माह ओवरटाइम',
  );
  static const kpiHoursNormal = _T(
    en: '{h} h normal',
    ar: '{h} س عادي',
    ur: '{h} گھنٹے عام',
    hi: '{h} घं सामान्य',
  );
  static const kpiHoursHoliday = _T(
    en: '{h} h holiday',
    ar: '{h} س عطلة',
    ur: '{h} گھنٹے چھٹی',
    hi: '{h} घं अवकाश',
  );
  static const kpiConfirmation = _T(
    en: '{month} confirmation',
    ar: 'تأكيد {month}',
    ur: '{month} کی تصدیق',
    hi: '{month} की पुष्टि',
  );
  static const kpiNotified = _T(
    en: 'Reviewers are reminded from {date} until confirmed',
    ar: 'يُذكَّر المراجعون من {date} حتى التأكيد',
    ur: 'جائزہ لینے والوں کو {date} سے تصدیق تک یاد دہانی ہوگی',
    hi: 'समीक्षकों को {date} से पुष्टि तक याद दिलाया जाएगा',
  );
  static const kpiNotifiedToday = _T(
    en: 'Reviewers notified today',
    ar: 'تم إبلاغ المراجعين اليوم',
    ur: 'جائزہ لینے والوں کو آج اطلاع دی گئی',
    hi: 'समीक्षकों को आज सूचित किया गया',
  );
  static const crewsCardSub = _T(
    en: 'Last 8 days. Hours are this month’s overtime.',
    ar: 'آخر 8 أيام. الساعات هي العمل الإضافي لهذا الشهر.',
    ur: 'پچھلے 8 دن۔ گھنٹے اس مہینے کا اوور ٹائم ہیں۔',
    hi: 'पिछले 8 दिन। घंटे इस माह का ओवरटाइम हैं।',
  );
  static const colCrew = _T(en: 'Crew', ar: 'الطاقم', ur: 'عملہ', hi: 'दल');
  static const colLast8 = _T(
    en: 'Last 8 days',
    ar: 'آخر 8 أيام',
    ur: 'پچھلے 8 دن',
    hi: 'पिछले 8 दिन',
  );
  static const colDaysEntered = _T(
    en: 'Days entered',
    ar: 'الأيام المُدخلة',
    ur: 'درج دن',
    hi: 'दर्ज दिन',
  );
  static const colOtNormal = _T(
    en: 'OT normal h',
    ar: 'إضافي عادي س',
    ur: 'اوور ٹائم عام گھنٹے',
    hi: 'ओटी सामान्य घं',
  );
  static const colOtHoliday = _T(
    en: 'OT holiday h',
    ar: 'إضافي عطلة س',
    ur: 'اوور ٹائم چھٹی گھنٹے',
    hi: 'ओटी अवकाश घं',
  );
  static const colMonth = _T(en: 'Month', ar: 'الشهر', ur: 'مہینہ', hi: 'माह');
  static const daysOf = _T(
    en: '{a} of {b}',
    ar: '{a} من {b}',
    ur: '{b} میں سے {a}',
    hi: '{b} में से {a}',
  );
  static const workersCount = _T(
    en: '{n} workers',
    ar: '{n} عمال',
    ur: '{n} ورکرز',
    hi: '{n} कर्मचारी',
  );
  static const feedTitle = _T(
    en: 'What’s happening',
    ar: 'ما يحدث',
    ur: 'کیا ہو رہا ہے',
    hi: 'क्या हो रहा है',
  );
  static const feedSub = _T(
    en: 'Every entry, change and question, newest first.',
    ar: 'كل إدخال وتغيير وسؤال، الأحدث أولًا.',
    ur: 'ہر اندراج، تبدیلی اور سوال، نیا پہلے۔',
    hi: 'हर प्रविष्टि, बदलाव और प्रश्न, नया पहले।',
  );
  static const feedEntered = _T(
    en: '{by} entered {crew} · {date}',
    ar: 'أدخل {by} {crew} · {date}',
    ur: '{by} نے {crew} درج کیا · {date}',
    hi: '{by} ने {crew} दर्ज किया · {date}',
  );
  static const feedChanged = _T(
    en: '{by} changed {crew} · {date}',
    ar: 'غيّر {by} {crew} · {date}',
    ur: '{by} نے {crew} تبدیل کیا · {date}',
    hi: '{by} ने {crew} बदला · {date}',
  );
  static const feedAsked = _T(
    en: '{by} asked about {crew} · {date}',
    ar: 'سأل {by} عن {crew} · {date}',
    ur: '{by} نے {crew} کے بارے میں پوچھا · {date}',
    hi: '{by} ने {crew} के बारे में पूछा · {date}',
  );
  static const feedAnswered = _T(
    en: '{by} answered on {crew} · {date}',
    ar: 'أجاب {by} على {crew} · {date}',
    ur: '{by} نے {crew} پر جواب دیا · {date}',
    hi: '{by} ने {crew} पर उत्तर दिया · {date}',
  );
  static const feedConfirmed = _T(
    en: '{by} confirmed {crew} · {date}',
    ar: 'أكد {by} {crew} · {date}',
    ur: '{by} نے {crew} کی تصدیق کی · {date}',
    hi: '{by} ने {crew} की पुष्टि की · {date}',
  );
  static const feedReopened = _T(
    en: '{by} reopened {crew} · {date}',
    ar: 'أعاد {by} فتح {crew} · {date}',
    ur: '{by} نے {crew} دوبارہ کھولا · {date}',
    hi: '{by} ने {crew} फिर खोला · {date}',
  );
  static const feedSummary = _T(
    en: '{p} present · {a} absent · {l} leave',
    ar: '{p} حاضر · {a} غائب · {l} إجازة',
    ur: '{p} حاضر · {a} غیر حاضر · {l} چھٹی',
    hi: '{p} उपस्थित · {a} अनुपस्थित · {l} अवकाश',
  );
  static const nothingYet = _T(
    en: 'Nothing yet.',
    ar: 'لا شيء بعد.',
    ur: 'ابھی کچھ نہیں۔',
    hi: 'अभी कुछ नहीं।',
  );
  static const noCrews = _T(
    en: 'No crews yet. A crew groups the workers you take attendance for.',
    ar: 'لا توجد طواقم بعد. الطاقم يجمع العمال الذين تسجل حضورهم.',
    ur: 'ابھی کوئی عملہ نہیں۔ عملہ ان ورکرز کا گروپ ہے جن کی آپ حاضری لگاتے ہیں۔',
    hi: 'अभी कोई दल नहीं। दल उन कर्मचारियों का समूह है जिनकी आप उपस्थिति दर्ज करते हैं।',
  );

  // ─── Take attendance ───────────────────────────────────────────────────────
  static const takeIntro = _T(
    en: 'Enter your crew for today or any earlier day. Your Project Engineer sees it straight away and confirms the whole month at month end.',
    ar: 'أدخل طاقمك لليوم أو لأي يوم سابق. يراه مهندس المشروع فورًا ويؤكد الشهر كاملًا في نهايته.',
    ur: 'آج یا کسی پچھلے دن کے لیے اپنا عملہ درج کریں۔ پروجیکٹ انجینئر فوراً دیکھتا ہے اور مہینے کے آخر میں پورے مہینے کی تصدیق کرتا ہے۔',
    hi: 'आज या किसी पिछले दिन के लिए अपना दल दर्ज करें। प्रोजेक्ट इंजीनियर तुरंत देखता है और माह के अंत में पूरे माह की पुष्टि करता है।',
  );
  static const takeIntroWorkshop = _T(
    en: 'Enter your crew for today or any earlier day. Workshop attendance needs no confirmation.',
    ar: 'أدخل طاقمك لليوم أو لأي يوم سابق. حضور الورشة لا يحتاج إلى تأكيد.',
    ur: 'آج یا کسی پچھلے دن کے لیے اپنا عملہ درج کریں۔ ورکشاپ کی حاضری کو تصدیق کی ضرورت نہیں۔',
    hi: 'आज या किसी पिछले दिन के लिए अपना दल दर्ज करें। वर्कशॉप उपस्थिति को पुष्टि की आवश्यकता नहीं।',
  );
  static const takeIntroViewer = _T(
    en: 'You can see every day as it is entered. Change a day or ask a question if something looks wrong.',
    ar: 'يمكنك رؤية كل يوم فور إدخاله. غيّر يومًا أو اطرح سؤالًا إذا بدا شيء خاطئًا.',
    ur: 'آپ ہر دن درج ہوتے ہی دیکھ سکتے ہیں۔ کچھ غلط لگے تو دن تبدیل کریں یا سوال پوچھیں۔',
    hi: 'आप हर दिन दर्ज होते ही देख सकते हैं। कुछ गलत लगे तो दिन बदलें या प्रश्न पूछें।',
  );
  static const notEnteredYet = _T(
    en: 'Not entered yet:',
    ar: 'لم يُدخل بعد:',
    ur: 'ابھی درج نہیں:',
    hi: 'अभी दर्ज नहीं:',
  );
  static const restBanner = _T(
    en: '{day} — usually a rest day. Everyone starts as rest day. Mark anyone who came; their hours count as holiday overtime.',
    ar: '{day} — عادةً يوم راحة. يبدأ الجميع كيوم راحة. حدّد من حضر؛ تُحسب ساعاته عملًا إضافيًا في عطلة.',
    ur: '{day} — عموماً چھٹی کا دن۔ سب چھٹی سے شروع ہوتے ہیں۔ جو آیا اسے حاضر کریں؛ اس کے گھنٹے چھٹی کا اوور ٹائم ہیں۔',
    hi: '{day} — आमतौर पर विश्राम दिवस। सभी विश्राम से शुरू होते हैं। जो आया उसे चिह्नित करें; उसके घंटे अवकाश ओवरटाइम हैं।',
  );
  static const holidayBanner = _T(
    en: 'Public holiday · {name}. Everyone starts as rest day; hours worked count as holiday overtime.',
    ar: 'عطلة رسمية · {name}. يبدأ الجميع كيوم راحة؛ تُحسب ساعات العمل عملًا إضافيًا في عطلة.',
    ur: 'سرکاری چھٹی · {name}۔ سب چھٹی سے شروع ہوتے ہیں؛ کام کے گھنٹے چھٹی کا اوور ٹائم ہیں۔',
    hi: 'सार्वजनिक अवकाश · {name}। सभी विश्राम से शुरू होते हैं; काम के घंटे अवकाश ओवरटाइम हैं।',
  );
  static const earlierBanner = _T(
    en: 'You are entering an earlier day. It will show as entered on {today}.',
    ar: 'أنت تُدخل يومًا سابقًا. سيظهر أنه أُدخل في {today}.',
    ur: 'آپ پچھلا دن درج کر رہے ہیں۔ یہ {today} کو درج دکھائی دے گا۔',
    hi: 'आप पिछला दिन दर्ज कर रहे हैं। यह {today} को दर्ज दिखेगा।',
  );
  static const askedBanner = _T(
    en: '{by} asked:',
    ar: 'سأل {by}:',
    ur: '{by} نے پوچھا:',
    hi: '{by} ने पूछा:',
  );
  static const answeredBy = _T(
    en: '{by} answered:',
    ar: 'أجاب {by}:',
    ur: '{by} نے جواب دیا:',
    hi: '{by} ने उत्तर दिया:',
  );
  static const yourAnswer = _T(
    en: 'Your answer',
    ar: 'إجابتك',
    ur: 'آپ کا جواب',
    hi: 'आपका उत्तर',
  );
  static const sendAnswer = _T(
    en: 'Send answer',
    ar: 'إرسال الإجابة',
    ur: 'جواب بھیجیں',
    hi: 'उत्तर भेजें',
  );
  static const changeLine = _T(
    en: '{by} changed {worker}: {what} — “{why}”',
    ar: 'غيّر {by} {worker}: {what} — «{why}»',
    ur: '{by} نے {worker} تبدیل کیا: {what} — “{why}”',
    hi: '{by} ने {worker} बदला: {what} — “{why}”',
  );
  static const removedFromDay = _T(
    en: 'taken off this day',
    ar: 'أُزيل من هذا اليوم',
    ur: 'اس دن سے ہٹایا گیا',
    hi: 'इस दिन से हटाया',
  );
  static const lockedBanner = _T(
    en: '{month} is confirmed by {name}. Days are locked.',
    ar: 'تم تأكيد {month} بواسطة {name}. الأيام مقفلة.',
    ur: '{month} کی تصدیق {name} نے کی۔ دن مقفل ہیں۔',
    hi: '{month} की पुष्टि {name} ने की। दिन लॉक हैं।',
  );
  static const copyDay = _T(
    en: 'Copy {date}',
    ar: 'نسخ {date}',
    ur: '{date} نقل کریں',
    hi: '{date} कॉपी करें',
  );
  static const everyonePresent = _T(
    en: 'Everyone present',
    ar: 'الجميع حاضر',
    ur: 'سب حاضر',
    hi: 'सभी उपस्थित',
  );
  static const shiftButton = _T(
    en: 'Shift {start} – {finish}',
    ar: 'الوردية {start} – {finish}',
    ur: 'شفٹ {start} – {finish}',
    hi: 'शिफ्ट {start} – {finish}',
  );
  static const addWorkerHint = _T(
    en: 'Add a worker — type any part of the name',
    ar: 'أضف عاملًا — اكتب أي جزء من الاسم',
    ur: 'ورکر شامل کریں — نام کا کوئی حصہ لکھیں',
    hi: 'कर्मचारी जोड़ें — नाम का कोई भी हिस्सा लिखें',
  );
  static const didYouMean = _T(
    en: 'Did you mean “{name}”?',
    ar: 'هل تقصد «{name}»؟',
    ur: 'کیا آپ کا مطلب “{name}” ہے؟',
    hi: 'क्या आपका मतलब “{name}” है?',
  );
  static const noMatchWorker = _T(
    en: 'No match — check the spelling or ask Admin or PR to add the worker.',
    ar: 'لا تطابق — تحقق من التهجئة أو اطلب من المسؤول أو العلاقات العامة إضافة العامل.',
    ur: 'کوئی میل نہیں — ہجے دیکھیں یا ایڈمن یا پی آر سے ورکر شامل کروائیں۔',
    hi: 'कोई मेल नहीं — वर्तनी जाँचें या एडमिन या पीआर से कर्मचारी जुड़वाएँ।',
  );
  static const fromCrew = _T(
    en: 'From {crew}',
    ar: 'من {crew}',
    ur: '{crew} سے',
    hi: '{crew} से',
  );
  static const labourPool = _T(
    en: 'Labour pool',
    ar: 'مجمع العمال',
    ur: 'لیبر پول',
    hi: 'श्रम पूल',
  );
  static const docsOk = _T(
    en: 'Documents OK',
    ar: 'المستندات سارية',
    ur: 'دستاویزات درست',
    hi: 'दस्तावेज़ ठीक',
  );
  static const docsExpiring = _T(
    en: 'Documents expiring',
    ar: 'مستندات تنتهي قريبًا',
    ur: 'دستاویزات جلد ختم',
    hi: 'दस्तावेज़ जल्द समाप्त',
  );
  static const docsExpired = _T(
    en: 'Documents expired',
    ar: 'مستندات منتهية',
    ur: 'دستاویزات ختم',
    hi: 'दस्तावेज़ समाप्त',
  );
  static const docsHint = _T(
    en: 'Ask PR to renew them.',
    ar: 'اطلب من العلاقات العامة تجديدها.',
    ur: 'تجدید کے لیے پی آر سے کہیں۔',
    hi: 'नवीनीकरण के लिए पीआर से कहें।',
  );
  static const changedChip = _T(
    en: 'Changed',
    ar: 'تم التغيير',
    ur: 'تبدیل شدہ',
    hi: 'बदला गया',
  );
  static const breakRange = _T(
    en: 'break {a}–{b}',
    ar: 'استراحة {a}–{b}',
    ur: 'وقفہ {a}–{b}',
    hi: 'विराम {a}–{b}',
  );
  static const otHours = _T(
    en: 'OT {h} h',
    ar: 'إضافي {h} س',
    ur: 'اوور ٹائم {h} گھنٹے',
    hi: 'ओटी {h} घं',
  );
  static const holHours = _T(
    en: 'HOL {h} h',
    ar: 'عطلة {h} س',
    ur: 'چھٹی {h} گھنٹے',
    hi: 'अवकाश {h} घं',
  );
  static const colWorker = _T(
    en: 'Worker',
    ar: 'العامل',
    ur: 'ورکر',
    hi: 'कर्मचारी',
  );
  static const colStatus = _T(
    en: 'Status',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const colIn = _T(en: 'In', ar: 'دخول', ur: 'آمد', hi: 'आगमन');
  static const colBreak = _T(
    en: 'Break',
    ar: 'استراحة',
    ur: 'وقفہ',
    hi: 'विराम',
  );
  static const colBack = _T(en: 'Back', ar: 'عودة', ur: 'واپسی', hi: 'वापसी');
  static const colOut = _T(en: 'Out', ar: 'خروج', ur: 'روانگی', hi: 'प्रस्थान');
  static const colHours = _T(
    en: 'Hours',
    ar: 'الساعات',
    ur: 'گھنٹے',
    hi: 'घंटे',
  );
  static const colNormal = _T(
    en: 'Normal',
    ar: 'عادي',
    ur: 'عام',
    hi: 'सामान्य',
  );
  static const colOtNormalShort = _T(
    en: 'OT normal',
    ar: 'إضافي عادي',
    ur: 'اوور ٹائم عام',
    hi: 'ओटी सामान्य',
  );
  static const colOtHolidayShort = _T(
    en: 'OT holiday',
    ar: 'إضافي عطلة',
    ur: 'اوور ٹائم چھٹی',
    hi: 'ओटी अवकाश',
  );
  static const colProject = _T(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const timeHint = _T(
    en: 'Time · type 630, 1230, 1, 5',
    ar: 'الوقت · اكتب 630، 1230، 1، 5',
    ur: 'وقت · لکھیں 630، 1230، 1، 5',
    hi: 'समय · लिखें 630, 1230, 1, 5',
  );
  static const notATime = _T(
    en: 'Not a time',
    ar: 'ليس وقتًا',
    ur: 'یہ وقت نہیں',
    hi: 'यह समय नहीं',
  );
  static const outAt = _T(
    en: 'Out at',
    ar: 'الخروج في',
    ur: 'روانگی',
    hi: 'प्रस्थान',
  );
  static const noBreak = _T(
    en: 'No break',
    ar: 'بدون استراحة',
    ur: 'وقفہ نہیں',
    hi: 'कोई विराम नहीं',
  );
  static const addBreak = _T(
    en: 'Add break',
    ar: 'إضافة استراحة',
    ur: 'وقفہ شامل کریں',
    hi: 'विराम जोड़ें',
  );
  static const projectHint = _T(
    en: 'Start typing — e.g. swehan 321',
    ar: 'ابدأ الكتابة — مثل swehan 321',
    ur: 'لکھنا شروع کریں — جیسے swehan 321',
    hi: 'लिखना शुरू करें — जैसे swehan 321',
  );
  static const overtimeNote = _T(
    en: 'Overtime note · optional',
    ar: 'ملاحظة العمل الإضافي · اختياري',
    ur: 'اوور ٹائم نوٹ · اختیاری',
    hi: 'ओवरटाइम नोट · वैकल्पिक',
  );
  static const overtimeNoteHint = _T(
    en: 'Why the extra hours',
    ar: 'سبب الساعات الإضافية',
    ur: 'اضافی گھنٹوں کی وجہ',
    hi: 'अतिरिक्त घंटों का कारण',
  );
  static const noteConcrete = _T(
    en: 'Concrete pour',
    ar: 'صب الخرسانة',
    ur: 'کنکریٹ ڈالنا',
    hi: 'कंक्रीट डालना',
  );
  static const noteClient = _T(
    en: 'Client request',
    ar: 'طلب العميل',
    ur: 'کلائنٹ کی درخواست',
    hi: 'ग्राहक का अनुरोध',
  );
  static const noteShutdown = _T(
    en: 'Shutdown work',
    ar: 'أعمال إيقاف',
    ur: 'شٹ ڈاؤن کام',
    hi: 'शटडाउन कार्य',
  );
  static const noteUrgent = _T(
    en: 'Urgent delivery',
    ar: 'تسليم عاجل',
    ur: 'فوری ترسیل',
    hi: 'तत्काल डिलीवरी',
  );
  static const previous = _T(
    en: 'Previous',
    ar: 'السابق',
    ur: 'پچھلا',
    hi: 'पिछला',
  );
  static const saveNext = _T(
    en: 'Done · next',
    ar: 'تم · التالي',
    ur: 'ٹھیک · اگلا',
    hi: 'ठीक · अगला',
  );
  static const done = _T(en: 'Done', ar: 'تم', ur: 'ٹھیک', hi: 'ठीक');
  static const footerSummary = _T(
    en: '{p} present · {a} absent · {l} leave',
    ar: '{p} حاضر · {a} غائب · {l} إجازة',
    ur: '{p} حاضر · {a} غیر حاضر · {l} چھٹی',
    hi: '{p} उपस्थित · {a} अनुपस्थित · {l} अवकाश',
  );
  static const footerUnmarked = _T(
    en: '{n} not marked',
    ar: '{n} غير محدد',
    ur: '{n} درج نہیں',
    hi: '{n} अचिह्नित',
  );
  static const footerMissing = _T(
    en: '{n} time missing',
    ar: '{n} وقت ناقص',
    ur: '{n} وقت نامکمل',
    hi: '{n} समय अधूरा',
  );
  static const draftNote = _T(
    en: 'Saved on this device as you go. Your Project Engineer sees it once you save.',
    ar: 'يُحفظ على هذا الجهاز أثناء العمل. يراه مهندس المشروع بعد الحفظ.',
    ur: 'کام کرتے ہوئے اس ڈیوائس پر محفوظ ہوتا ہے۔ محفوظ کرنے کے بعد پروجیکٹ انجینئر دیکھتا ہے۔',
    hi: 'काम करते समय इस डिवाइस पर सहेजा जाता है। सहेजने के बाद प्रोजेक्ट इंजीनियर देखता है।',
  );
  static const draftNoteWorkshop = _T(
    en: 'Saved on this device as you go. No confirmation needed.',
    ar: 'يُحفظ على هذا الجهاز أثناء العمل. لا يلزم تأكيد.',
    ur: 'کام کرتے ہوئے اس ڈیوائس پر محفوظ ہوتا ہے۔ تصدیق کی ضرورت نہیں۔',
    hi: 'काम करते समय इस डिवाइस पर सहेजा जाता है। पुष्टि आवश्यक नहीं।',
  );
  static const saveDay = _T(
    en: 'Save {date}',
    ar: 'حفظ {date}',
    ur: '{date} محفوظ کریں',
    hi: '{date} सहेजें',
  );
  static const saveChanges = _T(
    en: 'Save changes',
    ar: 'حفظ التغييرات',
    ur: 'تبدیلیاں محفوظ کریں',
    hi: 'बदलाव सहेजें',
  );
  static const discardChanges = _T(
    en: 'Discard',
    ar: 'تجاهل',
    ur: 'رد کریں',
    hi: 'त्यागें',
  );
  static const enteredByLine = _T(
    en: 'Entered by {by} · {at}',
    ar: 'أدخله {by} · {at}',
    ur: '{by} نے درج کیا · {at}',
    hi: '{by} द्वारा दर्ज · {at}',
  );
  static const caughtUpLater = _T(
    en: '(caught up later)',
    ar: '(أُدخل لاحقًا)',
    ur: '(بعد میں درج)',
    hi: '(बाद में दर्ज)',
  );
  static const askQuestion = _T(
    en: 'Ask a question',
    ar: 'اطرح سؤالًا',
    ur: 'سوال پوچھیں',
    hi: 'प्रश्न पूछें',
  );
  static const notEnteredLine = _T(
    en: 'Not entered. An attendance taker for this crew can enter it.',
    ar: 'غير مُدخل. يمكن لمسجل حضور هذا الطاقم إدخاله.',
    ur: 'درج نہیں۔ اس عملے کا حاضری لینے والا اسے درج کر سکتا ہے۔',
    hi: 'दर्ज नहीं। इस दल का उपस्थिति लेने वाला इसे दर्ज कर सकता है।',
  );
  static const reasonTitle = _T(
    en: 'Why are you changing {date}?',
    ar: 'لماذا تغيّر {date}؟',
    ur: 'آپ {date} کیوں تبدیل کر رہے ہیں؟',
    hi: 'आप {date} क्यों बदल रहे हैं?',
  );
  static const reasonBody = _T(
    en: '{by} entered this day and will see your reason.',
    ar: 'أدخل {by} هذا اليوم وسيرى سببك.',
    ur: '{by} نے یہ دن درج کیا اور آپ کی وجہ دیکھے گا۔',
    hi: '{by} ने यह दिन दर्ज किया और आपका कारण देखेगा।',
  );
  static const reasonLabel = _T(
    en: 'Reason',
    ar: 'السبب',
    ur: 'وجہ',
    hi: 'कारण',
  );
  static const askTitle = _T(
    en: 'Your question about {date}',
    ar: 'سؤالك عن {date}',
    ur: '{date} کے بارے میں آپ کا سوال',
    hi: '{date} के बारे में आपका प्रश्न',
  );
  static const askBody = _T(
    en: '{by} will be notified and can answer on this day.',
    ar: 'سيتم إبلاغ {by} ويمكنه الإجابة في هذا اليوم.',
    ur: '{by} کو اطلاع ملے گی اور وہ اس دن پر جواب دے سکتا ہے۔',
    hi: '{by} को सूचना मिलेगी और वह इस दिन पर उत्तर दे सकता है।',
  );
  static const send = _T(en: 'Send', ar: 'إرسال', ur: 'بھیجیں', hi: 'भेजें');
  static const cancel = _T(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ',
    hi: 'रद्द करें',
  );
  static const savedToast = _T(
    en: '{date} saved.',
    ar: 'تم حفظ {date}.',
    ur: '{date} محفوظ ہو گیا۔',
    hi: '{date} सहेजा गया।',
  );
  static const savedNextToast = _T(
    en: '{date} saved. Next not entered: {next}.',
    ar: 'تم حفظ {date}. التالي غير المُدخل: {next}.',
    ur: '{date} محفوظ ہو گیا۔ اگلا غیر درج: {next}۔',
    hi: '{date} सहेजा गया। अगला अदर्ज: {next}।',
  );
  static const copiedToast = _T(
    en: 'Copied {date}. Change only what is different.',
    ar: 'تم نسخ {date}. غيّر ما يختلف فقط.',
    ur: '{date} نقل ہو گیا۔ صرف جو مختلف ہے بدلیں۔',
    hi: '{date} कॉपी हुआ। केवल जो अलग है वह बदलें।',
  );
  static const everyoneToast = _T(
    en: 'Everyone not yet marked is present on the usual shift. Change only the exceptions.',
    ar: 'كل من لم يُحدد بعد حاضر في الوردية المعتادة. غيّر الاستثناءات فقط.',
    ur: 'جو ابھی درج نہیں وہ معمول کی شفٹ پر حاضر ہیں۔ صرف استثنا بدلیں۔',
    hi: 'जो अभी अचिह्नित हैं वे सामान्य शिफ्ट पर उपस्थित हैं। केवल अपवाद बदलें।',
  );
  static const shiftTitle = _T(
    en: 'Usual shift for this crew',
    ar: 'الوردية المعتادة لهذا الطاقم',
    ur: 'اس عملے کی معمول کی شفٹ',
    hi: 'इस दल की सामान्य शिफ्ट',
  );
  static const shiftToast = _T(
    en: 'Shift set to {start} – {finish} for everyone present.',
    ar: 'ضُبطت الوردية {start} – {finish} لكل الحاضرين.',
    ur: 'تمام حاضر کے لیے شفٹ {start} – {finish}۔',
    hi: 'सभी उपस्थितों के लिए शिफ्ट {start} – {finish}।',
  );
  static const addedForDay = _T(
    en: '{name} added to {date} only.',
    ar: 'أُضيف {name} إلى {date} فقط.',
    ur: '{name} صرف {date} کے لیے شامل۔',
    hi: '{name} केवल {date} के लिए जोड़ा गया।',
  );
  static const sentToast = _T(
    en: 'Sent.',
    ar: 'تم الإرسال.',
    ur: 'بھیج دیا۔',
    hi: 'भेजा गया।',
  );
  static const unsavedChanges = _T(
    en: 'Unsaved changes on this device',
    ar: 'تغييرات غير محفوظة على هذا الجهاز',
    ur: 'اس ڈیوائس پر غیر محفوظ تبدیلیاں',
    hi: 'इस डिवाइस पर बिना सहेजे बदलाव',
  );
  static const usualShift = _T(
    en: 'Usual shift',
    ar: 'الوردية المعتادة',
    ur: 'معمول کی شفٹ',
    hi: 'सामान्य शिफ्ट',
  );
  static const chooseCrew = _T(
    en: 'Choose a crew',
    ar: 'اختر طاقمًا',
    ur: 'عملہ منتخب کریں',
    hi: 'दल चुनें',
  );

  // ─── Month confirmation ────────────────────────────────────────────────────
  static const confirmIntro = _T(
    en: 'You don’t need to approve each day. Everything entered is visible here as it happens; step in on any day if needed. On the last day of the month you get a notification to confirm.',
    ar: 'لا تحتاج إلى اعتماد كل يوم. كل ما يُدخل يظهر هنا فورًا؛ تدخّل في أي يوم عند الحاجة. في آخر يوم من الشهر يصلك إشعار للتأكيد.',
    ur: 'آپ کو ہر دن منظور کرنے کی ضرورت نہیں۔ جو درج ہو وہ یہاں فوراً نظر آتا ہے؛ ضرورت ہو تو کسی دن میں دخل دیں۔ مہینے کے آخری دن تصدیق کی اطلاع ملے گی۔',
    hi: 'आपको हर दिन स्वीकृत करने की आवश्यकता नहीं। जो दर्ज होता है वह यहाँ तुरंत दिखता है; ज़रूरत हो तो किसी दिन हस्तक्षेप करें। माह के अंतिम दिन पुष्टि की सूचना मिलेगी।',
  );
  static const nextConfirmation = _T(
    en: 'Next confirmation: {date}. Until then, days stay open for the attendance taker to fill in and correct.',
    ar: 'التأكيد التالي: {date}. حتى ذلك الحين تبقى الأيام مفتوحة لمسجل الحضور للإدخال والتصحيح.',
    ur: 'اگلی تصدیق: {date}۔ تب تک دن حاضری لینے والے کے لیے کھلے رہیں گے۔',
    hi: 'अगली पुष्टि: {date}। तब तक दिन उपस्थिति लेने वाले के लिए खुले रहेंगे।',
  );
  static const selectDay = _T(
    en: 'Select a day to open it',
    ar: 'اختر يومًا لفتحه',
    ur: 'کھولنے کے لیے دن منتخب کریں',
    hi: 'खोलने के लिए दिन चुनें',
  );
  static const daysEnteredLabel = _T(
    en: 'days entered',
    ar: 'أيام مُدخلة',
    ur: 'درج دن',
    hi: 'दर्ज दिन',
  );
  static const notEnteredLabel = _T(
    en: 'not entered',
    ar: 'غير مُدخلة',
    ur: 'درج نہیں',
    hi: 'दर्ज नहीं',
  );
  static const worthALook = _T(
    en: 'Worth a look',
    ar: 'يستحق النظر',
    ur: 'دیکھنے کے قابل',
    hi: 'देखने लायक',
  );
  static const flagOvertime = _T(
    en: '{worker} · {date}: {h} h overtime',
    ar: '{worker} · {date}: {h} س إضافي',
    ur: '{worker} · {date}: {h} گھنٹے اوور ٹائم',
    hi: '{worker} · {date}: {h} घं ओवरटाइम',
  );
  static const flagHoliday = _T(
    en: '{worker} · {date}: worked on a rest day ({h} h)',
    ar: '{worker} · {date}: عمل في يوم راحة ({h} س)',
    ur: '{worker} · {date}: چھٹی کے دن کام ({h} گھنٹے)',
    hi: '{worker} · {date}: विश्राम दिवस पर काम ({h} घं)',
  );
  static const flagQuestion = _T(
    en: '{date}: your question is not answered yet',
    ar: '{date}: لم يُجب على سؤالك بعد',
    ur: '{date}: آپ کے سوال کا ابھی جواب نہیں ملا',
    hi: '{date}: आपके प्रश्न का अभी उत्तर नहीं मिला',
  );
  static const moreFlags = _T(
    en: '+{n} more',
    ar: '+{n} أخرى',
    ur: '+{n} مزید',
    hi: '+{n} और',
  );
  static const confirmedAt = _T(
    en: 'Confirmed by {name} · {at}',
    ar: 'أكده {name} · {at}',
    ur: '{name} نے تصدیق کی · {at}',
    hi: '{name} द्वारा पुष्ट · {at}',
  );
  static const opensOn = _T(
    en: 'Opens on {date}. You will get a notification.',
    ar: 'يفتح في {date}. سيصلك إشعار.',
    ur: '{date} کو کھلے گا۔ آپ کو اطلاع ملے گی۔',
    hi: '{date} को खुलेगा। आपको सूचना मिलेगी।',
  );
  static const daysMissingList = _T(
    en: '{n} day(s) not entered: {list}',
    ar: '{n} يوم غير مُدخل: {list}',
    ur: '{n} دن درج نہیں: {list}',
    hi: '{n} दिन दर्ज नहीं: {list}',
  );
  static const allEnteredLocks = _T(
    en: 'Everything is entered. Confirming locks the month.',
    ar: 'تم إدخال كل شيء. التأكيد يقفل الشهر.',
    ur: 'سب درج ہے۔ تصدیق سے مہینہ مقفل ہو جائے گا۔',
    hi: 'सब दर्ज है। पुष्टि से माह लॉक हो जाएगा।',
  );
  static const confirmMonthButton = _T(
    en: 'Confirm {month}',
    ar: 'تأكيد {month}',
    ur: '{month} کی تصدیق کریں',
    hi: '{month} की पुष्टि करें',
  );
  static const confirmMonthQuestion = _T(
    en: 'Confirm {month} for {crew}? The month locks and PR and Accounts see it as final.',
    ar: 'تأكيد {month} لـ {crew}؟ يُقفل الشهر وتراه العلاقات العامة والحسابات نهائيًا.',
    ur: '{crew} کے لیے {month} کی تصدیق کریں؟ مہینہ مقفل ہو جائے گا اور پی آر اور اکاؤنٹس اسے حتمی دیکھیں گے۔',
    hi: '{crew} के लिए {month} की पुष्टि करें? माह लॉक होगा और पीआर व अकाउंट्स इसे अंतिम देखेंगे।',
  );
  static const confirmedToast = _T(
    en: '{crew} · {month} confirmed.',
    ar: '{crew} · تم تأكيد {month}.',
    ur: '{crew} · {month} کی تصدیق ہو گئی۔',
    hi: '{crew} · {month} पुष्ट हुआ।',
  );
  static const reopen = _T(
    en: 'Reopen',
    ar: 'إعادة فتح',
    ur: 'دوبارہ کھولیں',
    hi: 'फिर खोलें',
  );
  static const reopenQuestion = _T(
    en: 'Why are you reopening {month} for {crew}?',
    ar: 'لماذا تعيد فتح {month} لـ {crew}؟',
    ur: 'آپ {crew} کے لیے {month} کیوں دوبارہ کھول رہے ہیں؟',
    hi: 'आप {crew} के लिए {month} क्यों फिर खोल रहे हैं?',
  );
  static const reopenedToast = _T(
    en: '{month} reopened. Days can be corrected again.',
    ar: 'أُعيد فتح {month}. يمكن تصحيح الأيام مجددًا.',
    ur: '{month} دوبارہ کھل گیا۔ دن پھر درست کیے جا سکتے ہیں۔',
    hi: '{month} फिर खुला। दिन फिर सुधारे जा सकते हैं।',
  );
  static const noReviewCrews = _T(
    en: 'No crew you confirm needs attention.',
    ar: 'لا يوجد طاقم تؤكده يحتاج إلى انتباه.',
    ur: 'آپ کے تصدیق والے کسی عملے کو توجہ کی ضرورت نہیں۔',
    hi: 'आपके पुष्टि वाले किसी दल पर ध्यान की ज़रूरत नहीं।',
  );

  // ─── Monthly sheets ────────────────────────────────────────────────────────
  static const sheetsIntro = _T(
    en: 'The paper time sheet, filled from daily attendance. Until the reviewer confirms the month, figures can still change.',
    ar: 'كشف الدوام الورقي، يُملأ من الحضور اليومي. حتى يؤكد المراجع الشهر قد تتغير الأرقام.',
    ur: 'کاغذی ٹائم شیٹ، روزانہ حاضری سے بھری ہوئی۔ جب تک جائزہ لینے والا مہینے کی تصدیق نہ کرے، اعداد بدل سکتے ہیں۔',
    hi: 'कागज़ी टाइम शीट, दैनिक उपस्थिति से भरी। जब तक समीक्षक माह की पुष्टि न करे, आंकड़े बदल सकते हैं।',
  );
  static const print = _T(en: 'Print', ar: 'طباعة', ur: 'پرنٹ', hi: 'प्रिंट');
  static const savePdf = _T(
    en: 'Save PDF',
    ar: 'حفظ PDF',
    ur: 'PDF محفوظ کریں',
    hi: 'PDF सहेजें',
  );
  static const exportExcel = _T(
    en: 'Export Excel',
    ar: 'تصدير Excel',
    ur: 'Excel ایکسپورٹ',
    hi: 'Excel निर्यात',
  );
  static const workersIn = _T(
    en: 'Workers — {n} in {crew}',
    ar: 'العمال — {n} في {crew}',
    ur: 'ورکرز — {crew} میں {n}',
    hi: 'कर्मचारी — {crew} में {n}',
  );
  static const searchWorkerHint = _T(
    en: 'Search name or number — spelling can be rough',
    ar: 'ابحث بالاسم أو الرقم — التهجئة التقريبية مقبولة',
    ur: 'نام یا نمبر تلاش کریں — ہجے تقریبی چل جائیں گے',
    hi: 'नाम या नंबर खोजें — वर्तनी अनुमानित चलेगी',
  );
  static const noMatch = _T(
    en: 'No match.',
    ar: 'لا تطابق.',
    ur: 'کوئی میل نہیں۔',
    hi: 'कोई मेल नहीं।',
  );
  static const paperTitle = _T(
    en: 'DAILY TIME SHEET',
    ar: 'كشف الدوام اليومي',
    ur: 'روزانہ ٹائم شیٹ',
    hi: 'दैनिक टाइम शीट',
  );
  static const paperName = _T(
    en: 'Name:',
    ar: 'الاسم:',
    ur: 'نام:',
    hi: 'नाम:',
  );
  static const paperMonth = _T(
    en: 'Log for the month of:',
    ar: 'سجل شهر:',
    ur: 'مہینے کا ریکارڈ:',
    hi: 'माह का रिकॉर्ड:',
  );
  static const paperEmpId = _T(
    en: 'Emp. ID No.:',
    ar: 'رقم الموظف:',
    ur: 'ملازم نمبر:',
    hi: 'कर्मचारी संख्या:',
  );
  static const paperDesignation = _T(
    en: 'Designation:',
    ar: 'المسمى:',
    ur: 'عہدہ:',
    hi: 'पद:',
  );
  static const paperCrew = _T(
    en: 'Crew / project:',
    ar: 'الطاقم / المشروع:',
    ur: 'عملہ / پروجیکٹ:',
    hi: 'दल / प्रोजेक्ट:',
  );
  static const paperDate = _T(
    en: 'Date',
    ar: 'التاريخ',
    ur: 'تاریخ',
    hi: 'तारीख',
  );
  static const paperDay = _T(
    en: 'Day of the week',
    ar: 'اليوم',
    ur: 'ہفتے کا دن',
    hi: 'सप्ताह का दिन',
  );
  static const paperTime = _T(en: 'Time', ar: 'الوقت', ur: 'وقت', hi: 'समय');
  static const paperBrk = _T(en: 'Brk', ar: 'استراحة', ur: 'وقفہ', hi: 'विराम');
  static const paperOvertime = _T(
    en: 'Over time',
    ar: 'إضافي',
    ur: 'اوور ٹائم',
    hi: 'ओवरटाइम',
  );
  static const paperNor = _T(en: 'Nor.', ar: 'عادي', ur: 'عام', hi: 'सामान्य');
  static const paperHol = _T(en: 'Hol.', ar: 'عطلة', ur: 'چھٹی', hi: 'अवकाश');
  static const paperProject = _T(
    en: 'Project name',
    ar: 'اسم المشروع',
    ur: 'پروجیکٹ کا نام',
    hi: 'प्रोजेक्ट नाम',
  );
  static const paperSiteInCharge = _T(
    en: 'Site in-charge: entered by {names}',
    ar: 'مسؤول الموقع: أدخله {names}',
    ur: 'سائٹ انچارج: {names} نے درج کیا',
    hi: 'साइट प्रभारी: {names} द्वारा दर्ज',
  );
  static const paperTotal = _T(
    en: 'Total',
    ar: 'الإجمالي',
    ur: 'کل',
    hi: 'कुल',
  );
  static const paperTotalLine = _T(
    en: '{n} days present · {h} h normal',
    ar: '{n} يوم حضور · {h} س عادي',
    ur: '{n} دن حاضر · {h} گھنٹے عام',
    hi: '{n} दिन उपस्थित · {h} घं सामान्य',
  );
  static const statusConfirmed = _T(
    en: 'Confirmed',
    ar: 'مؤكد',
    ur: 'تصدیق شدہ',
    hi: 'पुष्ट',
  );
  static const statusEnteredChanged = _T(
    en: 'Entered · changed',
    ar: 'مُدخل · مُعدّل',
    ur: 'درج · تبدیل',
    hi: 'दर्ज · बदला',
  );
  static const fileSaved = _T(
    en: 'File saved.',
    ar: 'تم حفظ الملف.',
    ur: 'فائل محفوظ ہو گئی۔',
    hi: 'फ़ाइल सहेजी गई।',
  );
  static const fileFailed = _T(
    en: 'The file could not be made. Try again.',
    ar: 'تعذّر إنشاء الملف. حاول مرة أخرى.',
    ur: 'فائل نہیں بن سکی۔ دوبارہ کوشش کریں۔',
    hi: 'फ़ाइल नहीं बन सकी। फिर कोशिश करें।',
  );

  // ─── Crews ─────────────────────────────────────────────────────────────────
  static const newCrew = _T(
    en: 'New crew',
    ar: 'طاقم جديد',
    ur: 'نیا عملہ',
    hi: 'नया दल',
  );
  static const editCrew = _T(
    en: 'Edit crew',
    ar: 'تعديل الطاقم',
    ur: 'عملہ ترمیم',
    hi: 'दल संपादित करें',
  );
  static const crewName = _T(
    en: 'Crew name',
    ar: 'اسم الطاقم',
    ur: 'عملے کا نام',
    hi: 'दल का नाम',
  );
  static const crewKindProject = _T(
    en: 'Project crew',
    ar: 'طاقم مشروع',
    ur: 'پروجیکٹ عملہ',
    hi: 'प्रोजेक्ट दल',
  );
  static const crewKindWorkshop = _T(
    en: 'Workshop crew',
    ar: 'طاقم الورشة',
    ur: 'ورکشاپ عملہ',
    hi: 'वर्कशॉप दल',
  );
  static const needsConfirmation = _T(
    en: 'The month needs confirmation',
    ar: 'الشهر يحتاج إلى تأكيد',
    ur: 'مہینے کو تصدیق کی ضرورت ہے',
    hi: 'माह को पुष्टि चाहिए',
  );
  static const members = _T(
    en: 'Members',
    ar: 'الأعضاء',
    ur: 'اراکین',
    hi: 'सदस्य',
  );
  static const addWorkers = _T(
    en: 'Add workers',
    ar: 'إضافة عمال',
    ur: 'ورکرز شامل کریں',
    hi: 'कर्मचारी जोड़ें',
  );
  static const remove = _T(
    en: 'Remove',
    ar: 'إزالة',
    ur: 'ہٹائیں',
    hi: 'हटाएँ',
  );
  static const save = _T(en: 'Save', ar: 'حفظ', ur: 'محفوظ کریں', hi: 'सहेजें');
  static const moveWorker = _T(
    en: '{name} is in {crew}. Move to this crew?',
    ar: '{name} في {crew}. نقله إلى هذا الطاقم؟',
    ur: '{name} {crew} میں ہے۔ اس عملے میں منتقل کریں؟',
    hi: '{name} {crew} में है। इस दल में ले जाएँ?',
  );
  static const move = _T(
    en: 'Move',
    ar: 'نقل',
    ur: 'منتقل کریں',
    hi: 'ले जाएँ',
  );
  static const crewSaved = _T(
    en: 'Crew saved.',
    ar: 'تم حفظ الطاقم.',
    ur: 'عملہ محفوظ ہو گیا۔',
    hi: 'दल सहेजा गया।',
  );
  static const projectLabel = _T(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const workLabel = _T(
    en: 'Place shown on the sheet',
    ar: 'المكان الظاهر في الكشف',
    ur: 'شیٹ پر دکھائی جانے والی جگہ',
    hi: 'शीट पर दिखने वाला स्थान',
  );

  static const saving = _T(
    en: 'Saving…',
    ar: 'جارٍ الحفظ…',
    ur: 'محفوظ ہو رہا ہے…',
    hi: 'सहेजा जा रहा है…',
  );
  static const undo = _T(
    en: 'Undo',
    ar: 'تراجع',
    ur: 'واپس کریں',
    hi: 'पूर्ववत करें',
  );
  static const needText = _T(
    en: 'Type the {field} first.',
    ar: 'اكتب {field} أولًا.',
    ur: 'پہلے {field} لکھیں۔',
    hi: 'पहले {field} लिखें।',
  );
  static const keepMine = _T(
    en: 'Keep my entries',
    ar: 'احتفظ بإدخالاتي',
    ur: 'میرے اندراج رکھیں',
    hi: 'मेरी प्रविष्टियाँ रखें',
  );
  static const useTheirs = _T(
    en: 'Use the saved day',
    ar: 'استخدم اليوم المحفوظ',
    ur: 'محفوظ دن استعمال کریں',
    hi: 'सहेजा दिन उपयोग करें',
  );
  static const keptMine = _T(
    en: 'Your entries are on top of the saved day. Check them, then save.',
    ar: 'إدخالاتك فوق اليوم المحفوظ. راجعها ثم احفظ.',
    ur: 'آپ کے اندراج محفوظ دن پر ہیں۔ انہیں دیکھیں، پھر محفوظ کریں۔',
    hi: 'आपकी प्रविष्टियाँ सहेजे दिन पर हैं। जाँचें, फिर सहेजें।',
  );
  static const undoEveryone = _T(
    en: 'Everyone not yet marked is present on the usual shift.',
    ar: 'كل من لم يُحدد بعد حاضر في الوردية المعتادة.',
    ur: 'جو درج نہیں تھے وہ معمول کی شفٹ پر حاضر ہیں۔',
    hi: 'जो अचिह्नित थे वे सामान्य शिफ्ट पर उपस्थित हैं।',
  );
  static const unsavedDay = _T(
    en: 'Not saved yet',
    ar: 'لم يُحفظ بعد',
    ur: 'ابھی محفوظ نہیں',
    hi: 'अभी सहेजा नहीं',
  );
  static const unsavedDays = _T(
    en: 'Days with entries on this device, not saved yet:',
    ar: 'أيام بها إدخالات على هذا الجهاز ولم تُحفظ بعد:',
    ur: 'اس ڈیوائس پر اندراج والے دن، ابھی محفوظ نہیں:',
    hi: 'इस डिवाइस पर प्रविष्टियों वाले दिन, अभी सहेजे नहीं:',
  );
  static const removedForDay = _T(
    en: '{name} taken off this day.',
    ar: 'أُزيل {name} من هذا اليوم.',
    ur: '{name} اس دن سے ہٹایا گیا۔',
    hi: '{name} इस दिन से हटाया गया।',
  );
  static const markAs = _T(
    en: 'Mark {name} as {status}',
    ar: 'تحديد {name} كـ {status}',
    ur: '{name} کو {status} درج کریں',
    hi: '{name} को {status} चिह्नित करें',
  );
  static const moreStatuses = _T(
    en: 'Leave, rest day and times for {name}',
    ar: 'الإجازة ويوم الراحة والأوقات لـ {name}',
    ur: '{name} کے لیے چھٹی، آرام کا دن اور اوقات',
    hi: '{name} के लिए अवकाश, विश्राम दिवस और समय',
  );
  static const holidays = _T(
    en: 'Public holidays',
    ar: 'العطل الرسمية',
    ur: 'سرکاری چھٹیاں',
    hi: 'सार्वजनिक अवकाश',
  );
  static const holidaysSub = _T(
    en: 'Every hour worked on these days counts as holiday overtime, like the weekly off days.',
    ar: 'كل ساعة عمل في هذه الأيام تُحسب عملًا إضافيًا في عطلة، مثل أيام العطلة الأسبوعية.',
    ur: 'ان دنوں کا ہر گھنٹہ ہفتہ وار چھٹی کی طرح چھٹی کا اوور ٹائم ہے۔',
    hi: 'इन दिनों का हर घंटा साप्ताहिक अवकाश की तरह अवकाश ओवरटाइम है।',
  );
  static const addHoliday = _T(
    en: 'Add holiday',
    ar: 'إضافة عطلة',
    ur: 'چھٹی شامل کریں',
    hi: 'अवकाश जोड़ें',
  );
  static const holidayName = _T(
    en: 'Holiday name',
    ar: 'اسم العطلة',
    ur: 'چھٹی کا نام',
    hi: 'अवकाश का नाम',
  );
  static const holidayDate = _T(
    en: 'Date',
    ar: 'التاريخ',
    ur: 'تاریخ',
    hi: 'तारीख',
  );
  static const holidayRemoveQuestion = _T(
    en: 'Remove {name} on {date}? Hours on that day count as normal time again.',
    ar: 'إزالة {name} في {date}؟ تُحسب ساعات ذلك اليوم وقتًا عاديًا مجددًا.',
    ur: '{date} کو {name} ہٹائیں؟ اس دن کے گھنٹے پھر عام وقت شمار ہوں گے۔',
    hi: '{date} को {name} हटाएँ? उस दिन के घंटे फिर सामान्य समय गिने जाएँगे।',
  );
  static const noHolidays = _T(
    en: 'No public holidays this year yet.',
    ar: 'لا توجد عطل رسمية هذا العام بعد.',
    ur: 'اس سال ابھی کوئی سرکاری چھٹی نہیں۔',
    hi: 'इस वर्ष अभी कोई सार्वजनिक अवकाश नहीं।',
  );
  static const reports = _T(
    en: 'Print and export',
    ar: 'الطباعة والتصدير',
    ur: 'پرنٹ اور ایکسپورٹ',
    hi: 'प्रिंट और निर्यात',
  );

  static const dueToday = _T(
    en: '{month} ends today — confirm your crews’ attendance',
    ar: 'ينتهي {month} اليوم — أكد حضور طواقمك',
    ur: '{month} آج ختم ہو رہا ہے — اپنے عملے کی حاضری کی تصدیق کریں',
    hi: '{month} आज समाप्त — अपने दलों की उपस्थिति की पुष्टि करें',
  );
  static const dueOverdue = _T(
    en: '{month} is waiting for your confirmation',
    ar: '{month} بانتظار تأكيدك',
    ur: '{month} آپ کی تصدیق کا منتظر ہے',
    hi: '{month} आपकी पुष्टि की प्रतीक्षा में है',
  );
  static const dueCrews = _T(
    en: 'Waiting: {crews}. Confirming locks the month for PR and Accounts.',
    ar: 'بالانتظار: {crews}. التأكيد يقفل الشهر للعلاقات العامة والحسابات.',
    ur: 'منتظر: {crews}۔ تصدیق سے مہینہ پی آر اور اکاؤنٹس کے لیے مقفل ہو جاتا ہے۔',
    hi: 'प्रतीक्षा में: {crews}। पुष्टि से माह पीआर और अकाउंट्स के लिए लॉक होता है।',
  );
  static const dueMissing = _T(
    en: '{crew} ({n} days not entered)',
    ar: '{crew} ({n} أيام غير مُدخلة)',
    ur: '{crew} ({n} دن درج نہیں)',
    hi: '{crew} ({n} दिन दर्ज नहीं)',
  );
  static const dueMissingOne = _T(
    en: '{crew} (1 day not entered)',
    ar: '{crew} (يوم واحد غير مُدخل)',
    ur: '{crew} (1 دن درج نہیں)',
    hi: '{crew} (1 दिन दर्ज नहीं)',
  );
  static const confirmNow = _T(
    en: 'Confirm now',
    ar: 'أكّد الآن',
    ur: 'ابھی تصدیق کریں',
    hi: 'अभी पुष्टि करें',
  );

  // ─── Errors ────────────────────────────────────────────────────────────────
  static const errOffline = _T(
    en: 'You are offline. Connect to save; your entries stay on this device.',
    ar: 'أنت غير متصل. اتصل للحفظ؛ تبقى إدخالاتك على هذا الجهاز.',
    ur: 'آپ آف لائن ہیں۔ محفوظ کرنے کے لیے کنیکٹ کریں؛ اندراج اس ڈیوائس پر رہیں گے۔',
    hi: 'आप ऑफ़लाइन हैं। सहेजने के लिए कनेक्ट करें; प्रविष्टियाँ इस डिवाइस पर रहेंगी।',
  );
  static const errConflict = _T(
    en: 'Someone saved this day while you were editing. Your entries are kept; reload to see theirs.',
    ar: 'حفظ شخص آخر هذا اليوم أثناء تعديلك. إدخالاتك محفوظة؛ أعد التحميل لرؤية إدخالاته.',
    ur: 'آپ کی ترمیم کے دوران کسی اور نے یہ دن محفوظ کیا۔ آپ کے اندراج محفوظ ہیں؛ ان کے دیکھنے کے لیے ری لوڈ کریں۔',
    hi: 'आपके संपादन के दौरान किसी ने यह दिन सहेजा। आपकी प्रविष्टियाँ रखी गई हैं; उनकी देखने के लिए रीलोड करें।',
  );
  static const errLocked = _T(
    en: 'This month is confirmed and locked.',
    ar: 'هذا الشهر مؤكد ومقفل.',
    ur: 'یہ مہینہ تصدیق شدہ اور مقفل ہے۔',
    hi: 'यह माह पुष्ट और लॉक है।',
  );
  static const errFuture = _T(
    en: 'A day in the future cannot be entered.',
    ar: 'لا يمكن إدخال يوم في المستقبل.',
    ur: 'مستقبل کا دن درج نہیں ہو سکتا۔',
    hi: 'भविष्य का दिन दर्ज नहीं हो सकता।',
  );
  static const errUnmarked = _T(
    en: 'Mark every worker before saving.',
    ar: 'حدد كل عامل قبل الحفظ.',
    ur: 'محفوظ کرنے سے پہلے ہر ورکر درج کریں۔',
    hi: 'सहेजने से पहले हर कर्मचारी चिह्नित करें।',
  );
  static const errTime = _T(
    en: 'Every worker marked Present needs an In and an Out time.',
    ar: 'كل عامل حاضر يحتاج إلى وقت دخول وخروج.',
    ur: 'ہر حاضر ورکر کے لیے آمد اور روانگی کا وقت ضروری ہے۔',
    hi: 'हर उपस्थित कर्मचारी के लिए आगमन और प्रस्थान समय आवश्यक है।',
  );
  static const errRest = _T(
    en: 'Rest day is only for Sundays and public holidays.',
    ar: 'يوم الراحة لأيام الأحد والعطل الرسمية فقط.',
    ur: 'چھٹی کا دن صرف اتوار اور سرکاری چھٹیوں کے لیے ہے۔',
    hi: 'विश्राम दिवस केवल रविवार और सार्वजनिक अवकाश के लिए है।',
  );
  static const errOtherCrew = _T(
    en: 'A worker is already on another crew’s sheet that day.',
    ar: 'عامل موجود بالفعل في كشف طاقم آخر في ذلك اليوم.',
    ur: 'ایک ورکر اس دن پہلے ہی کسی اور عملے کی شیٹ پر ہے۔',
    hi: 'एक कर्मचारी उस दिन पहले से दूसरे दल की शीट पर है।',
  );
  static const errReason = _T(
    en: 'A reason is needed to change a day someone else entered.',
    ar: 'يلزم سبب لتغيير يوم أدخله شخص آخر.',
    ur: 'کسی اور کا درج کیا ہوا دن بدلنے کے لیے وجہ ضروری ہے۔',
    hi: 'किसी और का दर्ज दिन बदलने के लिए कारण आवश्यक है।',
  );
  static const errNotEnded = _T(
    en: 'The month can be confirmed from its last day.',
    ar: 'يمكن تأكيد الشهر من آخر يوم فيه.',
    ur: 'مہینے کی تصدیق اس کے آخری دن سے ہو سکتی ہے۔',
    hi: 'माह की पुष्टि उसके अंतिम दिन से हो सकती है।',
  );
  static const errIncomplete = _T(
    en: 'Some working days are not entered yet.',
    ar: 'بعض أيام العمل لم تُدخل بعد.',
    ur: 'کچھ کام کے دن ابھی درج نہیں۔',
    hi: 'कुछ कार्य दिवस अभी दर्ज नहीं।',
  );
  static const errDenied = _T(
    en: 'You do not have access to this crew.',
    ar: 'ليس لديك صلاحية على هذا الطاقم.',
    ur: 'آپ کو اس عملے تک رسائی نہیں۔',
    hi: 'आपको इस दल तक पहुँच नहीं।',
  );
  static const errCrewName = _T(
    en: 'Another crew already has this name.',
    ar: 'طاقم آخر يحمل هذا الاسم.',
    ur: 'اس نام کا عملہ پہلے سے موجود ہے۔',
    hi: 'इस नाम का दल पहले से है।',
  );
  static const errGeneric = _T(
    en: 'That did not work. Nothing was changed; try again.',
    ar: 'لم ينجح ذلك. لم يتغير شيء؛ حاول مرة أخرى.',
    ur: 'یہ کام نہیں ہوا۔ کچھ تبدیل نہیں ہوا؛ دوبارہ کوشش کریں۔',
    hi: 'यह नहीं हुआ। कुछ नहीं बदला; फिर कोशिश करें।',
  );
  static const retry = _T(
    en: 'Try again',
    ar: 'حاول مرة أخرى',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर कोशिश करें',
  );
  static const reload = _T(
    en: 'Reload',
    ar: 'إعادة التحميل',
    ur: 'ری لوڈ',
    hi: 'रीलोड',
  );
}
