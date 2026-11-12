/// Workforce Center and crew request copy (English, Arabic, Urdu, Hindi).
///
/// Placeholders in braces are filled with [CrewRequestStrings.t].
library;

import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_attendance_strings.dart';

typedef _T = TranslatableString;

abstract final class CrewRequestStrings {
  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => AttendanceStrings.t(value, language, v);

  // ─── Center ────────────────────────────────────────────────────────────────
  static const centerTitle = _T(
    en: 'Workforce Center',
    ar: 'مركز القوى العاملة',
    ur: 'ورک فورس سینٹر',
    hi: 'वर्कफ़ोर्स सेंटर',
  );
  static const centerShort = _T(
    en: 'Center',
    ar: 'المركز',
    ur: 'سینٹر',
    hi: 'सेंटर',
  );
  static const centerIntro = _T(
    en: 'What is waiting for you, crew requests and every crew in one place',
    ar: 'ما ينتظرك وطلبات الطواقم وكل الطواقم في مكان واحد',
    ur: 'آپ کا منتظر کام، عملے کی درخواستیں اور تمام عملے ایک جگہ',
    hi: 'आपका लंबित काम, क्रू अनुरोध और सभी क्रू एक जगह',
  );
  static const viewMyWork = _T(
    en: 'My work',
    ar: 'عملي',
    ur: 'میرا کام',
    hi: 'मेरा काम',
  );
  static const viewRequests = _T(
    en: 'Crew requests',
    ar: 'طلبات الطواقم',
    ur: 'عملے کی درخواستیں',
    hi: 'क्रू अनुरोध',
  );
  static const viewCrews = _T(
    en: 'Crews',
    ar: 'الطواقم',
    ur: 'عملے',
    hi: 'क्रू',
  );
  static const kpiOpenRequests = _T(
    en: 'Open crew requests',
    ar: 'طلبات طواقم مفتوحة',
    ur: 'کھلی عملے کی درخواستیں',
    hi: 'खुले क्रू अनुरोध',
  );
  static const kpiWaitingForYou = _T(
    en: '{n} waiting for you',
    ar: '{n} بانتظارك',
    ur: '{n} آپ کے منتظر',
    hi: '{n} आपकी प्रतीक्षा में',
  );
  static const kpiNothingForYou = _T(
    en: 'Nothing waiting for you',
    ar: 'لا شيء بانتظارك',
    ur: 'آپ کا کوئی کام منتظر نہیں',
    hi: 'आपके लिए कुछ लंबित नहीं',
  );
  static const requestCrew = _T(
    en: 'Request crew',
    ar: 'طلب طاقم',
    ur: 'عملہ طلب کریں',
    hi: 'क्रू माँगें',
  );
  static const myWorkEmpty = _T(
    en: 'Nothing is waiting for you right now.',
    ar: 'لا شيء بانتظارك الآن.',
    ur: 'اس وقت آپ کا کوئی کام منتظر نہیں۔',
    hi: 'अभी आपके लिए कुछ भी लंबित नहीं है।',
  );
  static const myWorkSub = _T(
    en: 'Oldest first. Each item opens where you finish it.',
    ar: 'الأقدم أولًا. كل بند يفتح حيث تُنهيه.',
    ur: 'پرانا پہلے۔ ہر کام وہیں کھلتا ہے جہاں اسے مکمل کرنا ہے۔',
    hi: 'पुराना पहले। हर काम वहीं खुलता है जहाँ उसे पूरा करना है।',
  );
  static const itemDayMissing = _T(
    en: 'Enter attendance · {crew}',
    ar: 'أدخل الحضور · {crew}',
    ur: 'حاضری درج کریں · {crew}',
    hi: 'उपस्थिति दर्ज करें · {crew}',
  );
  static const itemConfirm = _T(
    en: 'Confirm {month} · {crew}',
    ar: 'أكّد {month} · {crew}',
    ur: '{month} کی تصدیق کریں · {crew}',
    hi: '{month} की पुष्टि करें · {crew}',
  );
  static const itemRequest = _T(
    en: '{next} · {number}',
    ar: '{next} · {number}',
    ur: '{next} · {number}',
    hi: '{next} · {number}',
  );
  static const open = _T(en: 'Open', ar: 'فتح', ur: 'کھولیں', hi: 'खोलें');
  static const requestsEmpty = _T(
    en: 'No crew requests yet',
    ar: 'لا توجد طلبات طواقم بعد',
    ur: 'ابھی عملے کی کوئی درخواست نہیں',
    hi: 'अभी कोई क्रू अनुरोध नहीं',
  );
  static const requestsEmptyBody = _T(
    en: 'Ask for workers by name or by trade. An approver assigns them, then you take attendance until the work is done.',
    ar: 'اطلب عمالًا بالاسم أو بالمهنة. يعيّنهم المعتمِد، ثم تسجّل حضورهم حتى ينتهي العمل.',
    ur: 'نام یا ہنر کے ذریعے کارکن مانگیں۔ منظور کنندہ انہیں مقرر کرے گا، پھر کام ختم ہونے تک آپ حاضری لیں۔',
    hi: 'नाम या ट्रेड से कामगार माँगें। स्वीकृतकर्ता उन्हें सौंपेगा, फिर काम पूरा होने तक आप हाज़िरी लें।',
  );
  static const requestsSub = _T(
    en: 'Newest activity first',
    ar: 'الأحدث نشاطًا أولًا',
    ur: 'تازہ ترین سرگرمی پہلے',
    hi: 'नवीनतम गतिविधि पहले',
  );
  static const showClosed = _T(
    en: 'Show finished',
    ar: 'إظهار المنتهية',
    ur: 'مکمل شدہ دکھائیں',
    hi: 'पूर्ण दिखाएँ',
  );

  // ─── Columns and facts ─────────────────────────────────────────────────────
  static const colRequest = _T(
    en: 'Request',
    ar: 'الطلب',
    ur: 'درخواست',
    hi: 'अनुरोध',
  );
  static const colPeople = _T(
    en: 'People',
    ar: 'الأشخاص',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const colNeeded = _T(
    en: 'Needed from',
    ar: 'مطلوب من',
    ur: 'درکار از',
    hi: 'आवश्यक से',
  );
  static const colState = _T(
    en: 'State',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const colWith = _T(
    en: 'With',
    ar: 'لدى',
    ur: 'کس کے پاس',
    hi: 'किसके पास',
  );
  static const colNext = _T(
    en: 'Next step',
    ar: 'الخطوة التالية',
    ur: 'اگلا قدم',
    hi: 'अगला कदम',
  );
  static const colLastUpdate = _T(
    en: 'Last update',
    ar: 'آخر تحديث',
    ur: 'آخری اپڈیٹ',
    hi: 'अंतिम अपडेट',
  );
  static const assignedOf = _T(
    en: '{a} of {b} assigned',
    ar: 'تم تعيين {a} من {b}',
    ur: '{b} میں سے {a} مقرر',
    hi: '{b} में से {a} सौंपे',
  );
  static const workshop = _T(
    en: 'Workshop',
    ar: 'الورشة',
    ur: 'ورکشاپ',
    hi: 'वर्कशॉप',
  );
  static const neededNow = _T(
    en: 'Needed now',
    ar: 'مطلوب الآن',
    ur: 'ابھی درکار',
    hi: 'अभी आवश्यक',
  );
  static const byRoleAt = _T(
    en: '{name} · {role} · {at}',
    ar: '{name} · {role} · {at}',
    ur: '{name} · {role} · {at}',
    hi: '{name} · {role} · {at}',
  );

  // ─── States, owners, next steps ────────────────────────────────────────────
  static const stateSubmitted = _T(
    en: 'Waiting for approval',
    ar: 'بانتظار الموافقة',
    ur: 'منظوری کا انتظار',
    hi: 'स्वीकृति की प्रतीक्षा',
  );
  static const stateReturned = _T(
    en: 'Returned',
    ar: 'مُعاد',
    ur: 'واپس',
    hi: 'वापस',
  );
  static const stateApproved = _T(
    en: 'Approved · waiting for workers',
    ar: 'معتمد · بانتظار العمال',
    ur: 'منظور · کارکنوں کا انتظار',
    hi: 'स्वीकृत · कामगारों की प्रतीक्षा',
  );
  static const statePartial = _T(
    en: 'Partly assigned',
    ar: 'معيّن جزئيًا',
    ur: 'جزوی طور پر مقرر',
    hi: 'आंशिक रूप से सौंपा',
  );
  static const stateFulfilled = _T(
    en: 'Workers on site',
    ar: 'العمال في الموقع',
    ur: 'کارکن سائٹ پر',
    hi: 'कामगार साइट पर',
  );
  static const stateClosed = _T(en: 'Closed', ar: 'مغلق', ur: 'بند', hi: 'बंद');
  static const stateRejected = _T(
    en: 'Rejected',
    ar: 'مرفوض',
    ur: 'مسترد',
    hi: 'अस्वीकृत',
  );
  static const stateCancelled = _T(
    en: 'Cancelled',
    ar: 'ملغى',
    ur: 'منسوخ',
    hi: 'रद्द',
  );
  static const ownerProjectEngineer = _T(
    en: 'Project Engineer',
    ar: 'مهندس المشروع',
    ur: 'پروجیکٹ انجینئر',
    hi: 'प्रोजेक्ट इंजीनियर',
  );
  static const ownerRequester = _T(
    en: 'Requester',
    ar: 'مقدّم الطلب',
    ur: 'درخواست دہندہ',
    hi: 'अनुरोधकर्ता',
  );
  static const ownerPr = _T(
    en: 'Approver or PR',
    ar: 'المعتمِد أو العلاقات العامة',
    ur: 'منظور کنندہ یا پی آر',
    hi: 'स्वीकृतकर्ता या पीआर',
  );
  static const ownerNone = _T(en: '—', ar: '—', ur: '—', hi: '—');
  static const nextApprove = _T(
    en: 'Approve and assign, or return',
    ar: 'وافق وعيّن، أو أعد',
    ur: 'منظور کر کے مقرر کریں، یا واپس کریں',
    hi: 'स्वीकृत करके सौंपें, या वापस करें',
  );
  static const nextFix = _T(
    en: 'Fix and resubmit',
    ar: 'صحّح وأعد الإرسال',
    ur: 'درست کر کے دوبارہ بھیجیں',
    hi: 'सुधारें और फिर भेजें',
  );
  static const nextAssign = _T(
    en: 'Assign workers',
    ar: 'عيّن العمال',
    ur: 'کارکن مقرر کریں',
    hi: 'कामगार सौंपें',
  );
  static const nextWaiting = _T(
    en: 'Waiting for {who}',
    ar: 'بانتظار {who}',
    ur: '{who} کا انتظار',
    hi: '{who} की प्रतीक्षा',
  );
  static const nextDone = _T(
    en: 'Nothing left to do',
    ar: 'لا شيء متبقٍ',
    ur: 'کچھ باقی نہیں',
    hi: 'कुछ शेष नहीं',
  );

  // ─── Request form ──────────────────────────────────────────────────────────
  static const formTitleNew = _T(
    en: 'Request crew',
    ar: 'طلب طاقم',
    ur: 'عملہ طلب کریں',
    hi: 'क्रू माँगें',
  );
  static const formTitleFix = _T(
    en: 'Fix and resubmit {number}',
    ar: 'صحّح وأعد إرسال {number}',
    ur: '{number} درست کر کے دوبارہ بھیجیں',
    hi: '{number} सुधारें और फिर भेजें',
  );
  static const formIntro = _T(
    en: 'Say who you need and from when. Nothing is sent until you press Send.',
    ar: 'حدّد من تحتاج ومتى. لا يُرسل شيء حتى تضغط إرسال.',
    ur: 'بتائیں کون اور کب سے درکار ہے۔ بھیجیں دبانے تک کچھ نہیں جاتا۔',
    hi: 'बताएँ किसकी और कब से ज़रूरत है। भेजें दबाने तक कुछ नहीं जाता।',
  );
  static const forLabel = _T(
    en: 'For',
    ar: 'لأجل',
    ur: 'کے لیے',
    hi: 'किसके लिए',
  );
  static const kindProject = _T(
    en: 'A project',
    ar: 'مشروع',
    ur: 'ایک پروجیکٹ',
    hi: 'एक प्रोजेक्ट',
  );
  static const kindWorkshop = _T(
    en: 'The workshop',
    ar: 'الورشة',
    ur: 'ورکشاپ',
    hi: 'वर्कशॉप',
  );
  static const projectLabel = _T(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const workLabel = _T(
    en: 'Work or area (optional)',
    ar: 'العمل أو المنطقة (اختياري)',
    ur: 'کام یا جگہ (اختیاری)',
    hi: 'काम या क्षेत्र (वैकल्पिक)',
  );
  static const workHint = _T(
    en: 'Level 3 ductwork',
    ar: 'مجاري الهواء في الطابق 3',
    ur: 'تیسری منزل کی ڈکٹ ورک',
    hi: 'तीसरी मंज़िल डक्टवर्क',
  );
  static const neededFrom = _T(
    en: 'Needed from',
    ar: 'مطلوب من',
    ur: 'درکار از',
    hi: 'आवश्यक से',
  );
  static const neededUntil = _T(
    en: 'Until (optional)',
    ar: 'حتى (اختياري)',
    ur: 'تک (اختیاری)',
    hi: 'तक (वैकल्पिक)',
  );
  static const clearDate = _T(
    en: 'Clear',
    ar: 'مسح',
    ur: 'صاف کریں',
    hi: 'हटाएँ',
  );
  static const targetCrew = _T(
    en: 'Add to crew (optional)',
    ar: 'أضف إلى طاقم (اختياري)',
    ur: 'عملے میں شامل کریں (اختیاری)',
    hi: 'क्रू में जोड़ें (वैकल्पिक)',
  );
  static const targetCrewAny = _T(
    en: 'PR decides',
    ar: 'يقرر قسم العلاقات العامة',
    ur: 'پی آر طے کرے',
    hi: 'पीआर तय करे',
  );
  static const peopleNeeded = _T(
    en: 'People needed',
    ar: 'الأشخاص المطلوبون',
    ur: 'درکار افراد',
    hi: 'आवश्यक लोग',
  );
  static const trade = _T(
    en: 'Name or trade',
    ar: 'الاسم أو المهنة',
    ur: 'نام یا ہنر',
    hi: 'नाम या ट्रेड',
  );
  static const tradeHint = _T(
    en: 'Start typing a name or a trade',
    ar: 'ابدأ بكتابة اسم أو مهنة',
    ur: 'نام یا ہنر لکھنا شروع کریں',
    hi: 'नाम या ट्रेड लिखना शुरू करें',
  );
  static const howMany = _T(
    en: 'How many',
    ar: 'كم عددًا',
    ur: 'کتنے',
    hi: 'कितने',
  );
  static const lineNote = _T(
    en: 'Note (optional)',
    ar: 'ملاحظة (اختياري)',
    ur: 'نوٹ (اختیاری)',
    hi: 'टिप्पणी (वैकल्पिक)',
  );
  static const addTrade = _T(
    en: 'Add another person or trade',
    ar: 'أضف شخصًا أو مهنة أخرى',
    ur: 'ایک اور شخص یا ہنر شامل کریں',
    hi: 'एक और व्यक्ति या ट्रेड जोड़ें',
  );
  static const remove = _T(
    en: 'Remove',
    ar: 'إزالة',
    ur: 'ہٹائیں',
    hi: 'हटाएँ',
  );
  static const notesLabel = _T(
    en: 'Notes for the approver (optional)',
    ar: 'ملاحظات للمعتمِد (اختياري)',
    ur: 'منظور کرنے والے کے لیے نوٹ (اختیاری)',
    hi: 'स्वीकृतकर्ता के लिए टिप्पणी (वैकल्पिक)',
  );
  static const send = _T(
    en: 'Send request',
    ar: 'إرسال الطلب',
    ur: 'درخواست بھیجیں',
    hi: 'अनुरोध भेजें',
  );
  static const sendAgain = _T(
    en: 'Send again',
    ar: 'أرسل مجددًا',
    ur: 'دوبارہ بھیجیں',
    hi: 'फिर भेजें',
  );
  static const approvedOnSubmitHint = _T(
    en: 'You approve requests on this project, so it is approved when you send it. Assign the workers next.',
    ar: 'أنت تعتمد طلبات هذا المشروع، لذا يُعتمد عند الإرسال. عيّن العمال بعد ذلك.',
    ur: 'آپ اس پروجیکٹ کی درخواستیں منظور کرتے ہیں، اس لیے بھیجتے ہی منظور ہو گی۔ اس کے بعد کارکن مقرر کریں۔',
    hi: 'आप इस प्रोजेक्ट के अनुरोध स्वीकृत करते हैं, इसलिए भेजते ही स्वीकृत होगा। फिर कामगार सौंपें।',
  );
  static const waitsForApprovalHint = _T(
    en: 'The Project Engineer approves it and assigns the workers.',
    ar: 'يعتمده مهندس المشروع ويعيّن العمال.',
    ur: 'پروجیکٹ انجینئر منظور کرے گا اور کارکن مقرر کرے گا۔',
    hi: 'प्रोजेक्ट इंजीनियर स्वीकृत करेगा और कामगार सौंपेगा।',
  );
  static const errNoLines = _T(
    en: 'Add at least one trade with how many people.',
    ar: 'أضف مهنة واحدة على الأقل مع عدد الأشخاص.',
    ur: 'کم از کم ایک ہنر اور افراد کی تعداد شامل کریں۔',
    hi: 'कम से कम एक ट्रेड और लोगों की संख्या जोड़ें।',
  );
  static const errProject = _T(
    en: 'Choose the project.',
    ar: 'اختر المشروع.',
    ur: 'پروجیکٹ منتخب کریں۔',
    hi: 'प्रोजेक्ट चुनें।',
  );
  static const sentToast = _T(
    en: '{number} sent',
    ar: 'تم إرسال {number}',
    ur: '{number} بھیج دی گئی',
    hi: '{number} भेजा गया',
  );
  static const noProjects = _T(
    en: 'You are not on a project you can request crews for.',
    ar: 'لست ضمن مشروع يمكنك طلب طواقم له.',
    ur: 'آپ کسی ایسے پروجیکٹ پر نہیں جس کے لیے عملہ طلب کر سکیں۔',
    hi: 'आप किसी ऐसे प्रोजेक्ट पर नहीं हैं जिसके लिए क्रू माँग सकें।',
  );
  static const back = _T(
    en: 'Workforce Center',
    ar: 'مركز القوى العاملة',
    ur: 'ورک فورس سینٹر',
    hi: 'वर्कफ़ोर्स सेंटर',
  );

  // ─── Detail ────────────────────────────────────────────────────────────────
  static const factProject = projectLabel;
  static const factWork = _T(
    en: 'Work or area',
    ar: 'العمل أو المنطقة',
    ur: 'کام یا جگہ',
    hi: 'काम या क्षेत्र',
  );
  static const factNeeded = _T(
    en: 'Needed',
    ar: 'مطلوب',
    ur: 'درکار',
    hi: 'आवश्यक',
  );
  static const factRequestedBy = _T(
    en: 'Requested by',
    ar: 'طلبه',
    ur: 'درخواست دہندہ',
    hi: 'अनुरोधकर्ता',
  );
  static const factDecidedBy = _T(
    en: 'Decided by',
    ar: 'قرّره',
    ur: 'فیصلہ کنندہ',
    hi: 'निर्णयकर्ता',
  );
  static const factCrew = _T(en: 'Crew', ar: 'الطاقم', ur: 'عملہ', hi: 'क्रू');
  static const factNotes = _T(
    en: 'Notes',
    ar: 'ملاحظات',
    ur: 'نوٹس',
    hi: 'टिप्पणियाँ',
  );
  static const factReason = _T(
    en: 'Reason',
    ar: 'السبب',
    ur: 'وجہ',
    hi: 'कारण',
  );
  static const fromUntil = _T(
    en: '{from} to {until}',
    ar: 'من {from} إلى {until}',
    ur: '{from} سے {until} تک',
    hi: '{from} से {until} तक',
  );
  static const fromOnwards = _T(
    en: 'From {from}',
    ar: 'من {from}',
    ur: '{from} سے',
    hi: '{from} से',
  );
  static const linesTitle = _T(
    en: 'People',
    ar: 'الأشخاص',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const noOneYet = _T(
    en: 'No one assigned yet',
    ar: 'لم يُعيَّن أحد بعد',
    ur: 'ابھی کوئی مقرر نہیں',
    hi: 'अभी कोई नहीं सौंपा',
  );
  static const decisionFull = _T(
    en: 'Full',
    ar: 'كامل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const decisionPartial = _T(
    en: 'Partial',
    ar: 'جزئي',
    ur: 'جزوی',
    hi: 'आंशिक',
  );
  static const decisionCannot = _T(
    en: 'Cannot provide now',
    ar: 'لا يمكن توفيره الآن',
    ur: 'ابھی فراہم نہیں ہو سکتا',
    hi: 'अभी उपलब्ध नहीं',
  );
  static const historyTitle = _T(
    en: 'History',
    ar: 'السجل',
    ur: 'تاریخچہ',
    hi: 'इतिहास',
  );
  static const evSubmitted = _T(
    en: '{name} sent the request',
    ar: 'أرسل {name} الطلب',
    ur: '{name} نے درخواست بھیجی',
    hi: '{name} ने अनुरोध भेजा',
  );
  static const evResubmitted = _T(
    en: '{name} sent it again',
    ar: 'أرسله {name} مجددًا',
    ur: '{name} نے دوبارہ بھیجی',
    hi: '{name} ने फिर भेजा',
  );
  static const evApproved = _T(
    en: '{name} approved it',
    ar: 'وافق عليه {name}',
    ur: '{name} نے منظور کیا',
    hi: '{name} ने स्वीकृत किया',
  );
  static const evApprovedOnSubmit = _T(
    en: 'Approved on submit by {name}',
    ar: 'اعتُمد عند الإرسال بواسطة {name}',
    ur: '{name} نے بھیجتے ہی منظور کیا',
    hi: '{name} द्वारा भेजते ही स्वीकृत',
  );
  static const evReturned = _T(
    en: '{name} returned it',
    ar: 'أعاده {name}',
    ur: '{name} نے واپس کیا',
    hi: '{name} ने वापस किया',
  );
  static const evRejected = _T(
    en: '{name} rejected it',
    ar: 'رفضه {name}',
    ur: '{name} نے مسترد کیا',
    hi: '{name} ने अस्वीकार किया',
  );
  static const evCancelled = _T(
    en: '{name} cancelled it',
    ar: 'ألغاه {name}',
    ur: '{name} نے منسوخ کیا',
    hi: '{name} ने रद्द किया',
  );
  static const evAssigned = _T(
    en: '{name} assigned {n} to {crew}',
    ar: 'عيّن {name} {n} في {crew}',
    ur: '{name} نے {n} کو {crew} میں مقرر کیا',
    hi: '{name} ने {n} को {crew} में सौंपा',
  );
  static const evDecisions = _T(
    en: '{name} recorded what cannot be provided now',
    ar: 'سجّل {name} ما لا يمكن توفيره الآن',
    ur: '{name} نے درج کیا کہ ابھی کیا فراہم نہیں ہو سکتا',
    hi: '{name} ने दर्ज किया कि अभी क्या उपलब्ध नहीं',
  );
  static const evClosed = _T(
    en: '{name} closed it',
    ar: 'أغلقه {name}',
    ur: '{name} نے بند کیا',
    hi: '{name} ने बंद किया',
  );

  // ─── Commands ──────────────────────────────────────────────────────────────
  static const approve = _T(
    en: 'Approve',
    ar: 'موافقة',
    ur: 'منظور کریں',
    hi: 'स्वीकृत करें',
  );
  static const returnAction = _T(
    en: 'Return',
    ar: 'إعادة',
    ur: 'واپس کریں',
    hi: 'वापस करें',
  );
  static const reject = _T(
    en: 'Reject',
    ar: 'رفض',
    ur: 'مسترد کریں',
    hi: 'अस्वीकार करें',
  );
  static const cancelRequest = _T(
    en: 'Cancel request',
    ar: 'إلغاء الطلب',
    ur: 'درخواست منسوخ کریں',
    hi: 'अनुरोध रद्द करें',
  );
  static const fixResubmit = _T(
    en: 'Fix and resubmit',
    ar: 'صحّح وأعد الإرسال',
    ur: 'درست کر کے دوبارہ بھیجیں',
    hi: 'सुधारें और फिर भेजें',
  );
  static const assignWorkers = _T(
    en: 'Assign workers',
    ar: 'تعيين العمال',
    ur: 'کارکن مقرر کریں',
    hi: 'कामगार सौंपें',
  );
  static const closeRemaining = _T(
    en: 'Close what is left',
    ar: 'أغلق المتبقي',
    ur: 'باقی بند کریں',
    hi: 'शेष बंद करें',
  );
  static const reasonLabel = _T(
    en: 'Reason',
    ar: 'السبب',
    ur: 'وجہ',
    hi: 'कारण',
  );
  static const reasonOptional = _T(
    en: 'Reason (optional)',
    ar: 'السبب (اختياري)',
    ur: 'وجہ (اختیاری)',
    hi: 'कारण (वैकल्पिक)',
  );
  static const approveTitle = _T(
    en: 'Approve {number}?',
    ar: 'الموافقة على {number}؟',
    ur: '{number} منظور کریں؟',
    hi: '{number} स्वीकृत करें?',
  );
  static const approveBody = _T(
    en: 'It waits for workers. You or PR can assign them later.',
    ar: 'سينتظر العمال. يمكنك أنت أو العلاقات العامة تعيينهم لاحقًا.',
    ur: 'یہ کارکنوں کا انتظار کرے گی۔ آپ یا پی آر بعد میں مقرر کر سکتے ہیں۔',
    hi: 'यह कामगारों की प्रतीक्षा करेगा। आप या पीआर बाद में सौंप सकते हैं।',
  );
  static const returnTitle = _T(
    en: 'Return {number}?',
    ar: 'إعادة {number}؟',
    ur: '{number} واپس کریں؟',
    hi: '{number} वापस करें?',
  );
  static const returnBody = _T(
    en: 'Say what to change. The requester fixes it and sends it again.',
    ar: 'اذكر ما يجب تغييره. يصحّحه مقدّم الطلب ويرسله مجددًا.',
    ur: 'بتائیں کیا بدلنا ہے۔ درخواست دہندہ درست کر کے دوبارہ بھیجے گا۔',
    hi: 'बताएँ क्या बदलना है। अनुरोधकर्ता सुधारकर फिर भेजेगा।',
  );
  static const rejectTitle = _T(
    en: 'Reject {number}?',
    ar: 'رفض {number}؟',
    ur: '{number} مسترد کریں؟',
    hi: '{number} अस्वीकार करें?',
  );
  static const rejectBody = _T(
    en: 'The requester is told why. A rejected request cannot be sent again.',
    ar: 'سيُبلَّغ مقدّم الطلب بالسبب. لا يمكن إعادة إرسال طلب مرفوض.',
    ur: 'درخواست دہندہ کو وجہ بتائی جائے گی۔ مسترد درخواست دوبارہ نہیں بھیجی جا سکتی۔',
    hi: 'अनुरोधकर्ता को कारण बताया जाएगा। अस्वीकृत अनुरोध फिर नहीं भेजा जा सकता।',
  );
  static const cancelTitle = _T(
    en: 'Cancel {number}?',
    ar: 'إلغاء {number}؟',
    ur: '{number} منسوخ کریں؟',
    hi: '{number} रद्द करें?',
  );
  static const cancelBody = _T(
    en: 'Nobody has been assigned yet. The request stays in the history.',
    ar: 'لم يُعيَّن أحد بعد. يبقى الطلب في السجل.',
    ur: 'ابھی کوئی مقرر نہیں ہوا۔ درخواست تاریخچے میں رہے گی۔',
    hi: 'अभी कोई नहीं सौंपा गया। अनुरोध इतिहास में रहेगा।',
  );
  static const closeTitle = _T(
    en: 'Close {number}?',
    ar: 'إغلاق {number}؟',
    ur: '{number} بند کریں؟',
    hi: '{number} बंद करें?',
  );
  static const closeBody = _T(
    en: 'Lines still short are closed with your reason. Workers already assigned stay on their crew.',
    ar: 'تُغلق البنود الناقصة بسببك. يبقى العمال المعيّنون في طواقمهم.',
    ur: 'کم رہ جانے والی لائنیں آپ کی وجہ سے بند ہوں گی۔ مقرر کارکن اپنے عملے میں رہیں گے۔',
    hi: 'कम रह गई पंक्तियाँ आपके कारण से बंद होंगी। सौंपे गए कामगार अपने क्रू में रहेंगे।',
  );
  static const keep = _T(
    en: 'Keep it',
    ar: 'إبقاء',
    ur: 'رہنے دیں',
    hi: 'रहने दें',
  );
  static const approvedToast = _T(
    en: 'Approved · waiting for workers',
    ar: 'تمت الموافقة · بانتظار العمال',
    ur: 'منظور · کارکنوں کا انتظار',
    hi: 'स्वीकृत · कामगारों की प्रतीक्षा',
  );
  static const returnedToast = _T(
    en: 'Returned to {name}',
    ar: 'أُعيد إلى {name}',
    ur: '{name} کو واپس کیا گیا',
    hi: '{name} को वापस किया गया',
  );
  static const rejectedToast = _T(
    en: 'Rejected',
    ar: 'تم الرفض',
    ur: 'مسترد',
    hi: 'अस्वीकृत',
  );
  static const cancelledToast = _T(
    en: 'Cancelled',
    ar: 'تم الإلغاء',
    ur: 'منسوخ',
    hi: 'रद्द',
  );
  static const closedToast = _T(
    en: 'Closed',
    ar: 'تم الإغلاق',
    ur: 'بند',
    hi: 'बंद',
  );

  // ─── Assign (PR) ───────────────────────────────────────────────────────────
  static const assignTitle = _T(
    en: 'Assign workers · {number}',
    ar: 'تعيين العمال · {number}',
    ur: 'کارکن مقرر کریں · {number}',
    hi: 'कामगार सौंपें · {number}',
  );
  static const assignIntro = _T(
    en: 'Choose free workers for each line. A line left short needs Partial or Cannot provide now, with a reason.',
    ar: 'اختر عمالًا متاحين لكل بند. البند الناقص يحتاج «جزئي» أو «لا يمكن توفيره الآن» مع السبب.',
    ur: 'ہر لائن کے لیے فارغ کارکن چنیں۔ کم رہ جانے والی لائن کے لیے جزوی یا ابھی فراہم نہیں، وجہ کے ساتھ درکار ہے۔',
    hi: 'हर पंक्ति के लिए खाली कामगार चुनें। कम रह गई पंक्ति के लिए आंशिक या अभी उपलब्ध नहीं, कारण सहित चाहिए।',
  );
  static const joinCrew = _T(
    en: 'Workers join',
    ar: 'ينضم العمال إلى',
    ur: 'کارکن شامل ہوں گے',
    hi: 'कामगार जुड़ेंगे',
  );
  static const existingCrew = _T(
    en: 'An existing crew',
    ar: 'طاقم موجود',
    ur: 'موجودہ عملہ',
    hi: 'मौजूदा क्रू',
  );
  static const newCrew = _T(
    en: 'A new crew',
    ar: 'طاقم جديد',
    ur: 'نیا عملہ',
    hi: 'नया क्रू',
  );
  static const crewLabel = factCrew;
  static const newCrewName = _T(
    en: 'New crew name',
    ar: 'اسم الطاقم الجديد',
    ur: 'نئے عملے کا نام',
    hi: 'नए क्रू का नाम',
  );
  static const shiftStarts = _T(
    en: 'Shift starts',
    ar: 'تبدأ الوردية',
    ur: 'شفٹ شروع',
    hi: 'शिफ़्ट शुरू',
  );
  static const shiftEnds = _T(
    en: 'Shift ends',
    ar: 'تنتهي الوردية',
    ur: 'شفٹ ختم',
    hi: 'शिफ़्ट समाप्त',
  );
  static const searchWorkers = _T(
    en: 'Search free workers',
    ar: 'ابحث عن عمال متاحين',
    ur: 'فارغ کارکن تلاش کریں',
    hi: 'खाली कामगार खोजें',
  );
  static const chosenOf = _T(
    en: '{a} of {b} chosen',
    ar: 'تم اختيار {a} من {b}',
    ur: '{b} میں سے {a} منتخب',
    hi: '{b} में से {a} चुने',
  );
  static const alreadyAssigned = _T(
    en: 'Already assigned: {names}',
    ar: 'معيّنون مسبقًا: {names}',
    ur: 'پہلے سے مقرر: {names}',
    hi: 'पहले से सौंपे: {names}',
  );
  static const whyShort = _T(
    en: 'Why is it short?',
    ar: 'لماذا هو ناقص؟',
    ur: 'کمی کیوں ہے؟',
    hi: 'कमी क्यों है?',
  );
  static const lineComplete = _T(
    en: 'Complete',
    ar: 'مكتمل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const saveAssign = _T(
    en: 'Assign {n}',
    ar: 'عيّن {n}',
    ur: '{n} مقرر کریں',
    hi: '{n} सौंपें',
  );
  static const saveDecisions = _T(
    en: 'Save',
    ar: 'حفظ',
    ur: 'محفوظ کریں',
    hi: 'सहेजें',
  );
  static const assignedToast = _T(
    en: 'Saved · the requester has been told',
    ar: 'تم الحفظ · أُبلغ مقدّم الطلب',
    ur: 'محفوظ · درخواست دہندہ کو بتا دیا گیا',
    hi: 'सहेजा गया · अनुरोधकर्ता को सूचित किया गया',
  );
  static const errReasonMissing = _T(
    en: 'Give a reason for each line left short.',
    ar: 'اذكر سببًا لكل بند ناقص.',
    ur: 'ہر کم رہ جانے والی لائن کی وجہ بتائیں۔',
    hi: 'कम रह गई हर पंक्ति का कारण बताएँ।',
  );
  static const errCrewMissing = _T(
    en: 'Choose a crew or name a new one.',
    ar: 'اختر طاقمًا أو سمِّ طاقمًا جديدًا.',
    ur: 'عملہ منتخب کریں یا نئے عملے کا نام دیں۔',
    hi: 'क्रू चुनें या नए क्रू का नाम दें।',
  );
  static const errNothingToSave = _T(
    en: 'Choose workers, or mark a line Partial or Cannot provide now.',
    ar: 'اختر عمالًا، أو حدّد بندًا «جزئي» أو «لا يمكن توفيره الآن».',
    ur: 'کارکن چنیں، یا لائن کو جزوی یا ابھی فراہم نہیں نشان زد کریں۔',
    hi: 'कामगार चुनें, या पंक्ति को आंशिक या अभी उपलब्ध नहीं चिह्नित करें।',
  );
  static const errWorkerOnCrew = _T(
    en: 'A chosen worker joined another crew meanwhile. Refresh and choose again.',
    ar: 'انضم أحد العمال المختارين إلى طاقم آخر. حدّث واختر مجددًا.',
    ur: 'ایک منتخب کارکن اس دوران دوسرے عملے میں شامل ہو گیا۔ ریفریش کر کے دوبارہ چنیں۔',
    hi: 'चुना गया एक कामगार इस बीच दूसरे क्रू में चला गया। रीफ़्रेश करके फिर चुनें।',
  );
  static const errOverAssigned = _T(
    en: 'A line has more workers than were asked for.',
    ar: 'بند فيه عمال أكثر من المطلوب.',
    ur: 'ایک لائن میں مانگ سے زیادہ کارکن ہیں۔',
    hi: 'एक पंक्ति में माँग से अधिक कामगार हैं।',
  );
  static const noFreeWorkers = _T(
    en: 'No free workers match. Add workers in Worker Records, or mark the line with a reason.',
    ar: 'لا يوجد عمال متاحون مطابقون. أضف عمالًا في سجلات العمال، أو حدّد البند مع السبب.',
    ur: 'کوئی فارغ کارکن نہیں ملا۔ ورکر ریکارڈز میں کارکن شامل کریں، یا لائن کو وجہ کے ساتھ نشان زد کریں۔',
    hi: 'कोई खाली कामगार नहीं मिला। वर्कर रिकॉर्ड्स में कामगार जोड़ें, या पंक्ति को कारण सहित चिह्नित करें।',
  );

  // ─── Material Request style flow ───────────────────────────────────────────
  static const stepDetails = _T(
    en: 'Details',
    ar: 'التفاصيل',
    ur: 'تفصیلات',
    hi: 'विवरण',
  );
  static const stepPeople = _T(
    en: 'People',
    ar: 'الأشخاص',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const stepReview = _T(
    en: 'Review',
    ar: 'المراجعة',
    ur: 'جائزہ',
    hi: 'समीक्षा',
  );
  static const eyebrow = _T(
    en: 'Crew request',
    ar: 'طلب طاقم',
    ur: 'عملے کی درخواست',
    hi: 'क्रू अनुरोध',
  );
  static const detailsPrompt = _T(
    en: 'Who needs workers?',
    ar: 'من يحتاج إلى عمال؟',
    ur: 'کسے کارکن چاہییں؟',
    hi: 'किसे कामगार चाहिए?',
  );
  static const detailsDescription = _T(
    en: 'Choose the project, the work and when the people are needed.',
    ar: 'اختر المشروع والعمل ومتى يلزم الأشخاص.',
    ur: 'پروجیکٹ، کام اور افراد کب درکار ہیں منتخب کریں۔',
    hi: 'प्रोजेक्ट, काम और लोग कब चाहिए चुनें।',
  );
  static const peoplePrompt = _T(
    en: 'Which people do you need?',
    ar: 'ما الأشخاص الذين تحتاجهم؟',
    ur: 'آپ کو کون سے افراد چاہییں؟',
    hi: 'आपको कौन से लोग चाहिए?',
  );
  static const peopleDescription = _T(
    en: 'Type a name to ask for a person, or a trade and how many.',
    ar: 'اكتب اسمًا لطلب شخص بعينه، أو مهنة والعدد.',
    ur: 'کسی شخص کے لیے نام لکھیں، یا ہنر اور تعداد۔',
    hi: 'किसी व्यक्ति के लिए नाम लिखें, या ट्रेड और संख्या।',
  );
  static const reviewPrompt = _T(
    en: 'Review and send',
    ar: 'المراجعة والإرسال',
    ur: 'جائزہ لیں اور بھیجیں',
    hi: 'समीक्षा करें और भेजें',
  );
  static const reviewDescription = _T(
    en: 'Check the request and who approves it before sending.',
    ar: 'تحقق من الطلب ومن يعتمده قبل الإرسال.',
    ur: 'بھیجنے سے پہلے درخواست اور منظور کنندہ کو دیکھ لیں۔',
    hi: 'भेजने से पहले अनुरोध और स्वीकृतकर्ता जाँच लें।',
  );
  static const continueAction = _T(
    en: 'Continue',
    ar: 'متابعة',
    ur: 'جاری رکھیں',
    hi: 'जारी रखें',
  );
  static const backAction = _T(en: 'Back', ar: 'رجوع', ur: 'واپس', hi: 'वापस');
  static const reviewAction = _T(
    en: 'Review',
    ar: 'مراجعة',
    ur: 'جائزہ',
    hi: 'समीक्षा',
  );
  static const ready = _T(en: 'Ready', ar: 'جاهز', ur: 'تیار', hi: 'तैयार');
  static const required = _T(
    en: 'Required',
    ar: 'مطلوب',
    ur: 'درکار',
    hi: 'आवश्यक',
  );
  static const rowWhere = _T(
    en: 'Project and dates',
    ar: 'المشروع والتواريخ',
    ur: 'پروجیکٹ اور تاریخیں',
    hi: 'प्रोजेक्ट और तारीखें',
  );
  static const rowPeople = _T(
    en: 'People needed',
    ar: 'الأشخاص المطلوبون',
    ur: 'درکار افراد',
    hi: 'आवश्यक लोग',
  );
  static const rowRoute = _T(
    en: 'Approval route',
    ar: 'مسار الاعتماد',
    ur: 'منظوری کا راستہ',
    hi: 'स्वीकृति मार्ग',
  );
  static const routeToPe = _T(
    en: 'Goes to the project\'s Project Engineer, who approves it and assigns the workers.',
    ar: 'يذهب إلى مهندس المشروع ليعتمده ويعيّن العمال.',
    ur: 'پروجیکٹ انجینئر کو جائے گی، جو منظور کر کے کارکن مقرر کرے گا۔',
    hi: 'प्रोजेक्ट इंजीनियर को जाएगा, जो स्वीकृत करके कामगार सौंपेगा।',
  );
  static const routeAuto = _T(
    en: 'Approved when you send it; assign the workers next.',
    ar: 'يُعتمد عند الإرسال؛ ثم عيّن العمال.',
    ur: 'بھیجتے ہی منظور؛ پھر کارکن مقرر کریں۔',
    hi: 'भेजते ही स्वीकृत; फिर कामगार सौंपें।',
  );
  static const requestSummary = _T(
    en: 'Request summary',
    ar: 'ملخص الطلب',
    ur: 'درخواست کا خلاصہ',
    hi: 'अनुरोध सारांश',
  );
  static const completeRequest = _T(
    en: 'Complete your request',
    ar: 'أكمل طلبك',
    ur: 'اپنی درخواست مکمل کریں',
    hi: 'अपना अनुरोध पूरा करें',
  );
  static const completeRequestMessage = _T(
    en: 'Send unlocks when the project, dates and people are ready.',
    ar: 'يتاح الإرسال عند تجهيز المشروع والتواريخ والأشخاص.',
    ur: 'پروجیکٹ، تاریخیں اور افراد تیار ہونے پر بھیجنا ممکن ہوگا۔',
    hi: 'प्रोजेक्ट, तारीखें और लोग तैयार होने पर भेज सकेंगे।',
  );
  static const peopleCount = _T(
    en: 'People: {n}',
    ar: 'الأشخاص: {n}',
    ur: 'افراد: {n}',
    hi: 'लोग: {n}',
  );
  static const registerTitle = _T(
    en: 'Crew Requests',
    ar: 'طلبات الطواقم',
    ur: 'عملے کی درخواستیں',
    hi: 'क्रू अनुरोध',
  );
  static const searchHint = _T(
    en: 'Search number, project or trade',
    ar: 'ابحث بالرقم أو المشروع أو المهنة',
    ur: 'نمبر، پروجیکٹ یا ہنر تلاش کریں',
    hi: 'संख्या, प्रोजेक्ट या ट्रेड खोजें',
  );
  static const filterMyWork = _T(
    en: 'My work',
    ar: 'عملي',
    ur: 'میرا کام',
    hi: 'मेरा काम',
  );
  static const filterOpen = _T(
    en: 'Open',
    ar: 'مفتوحة',
    ur: 'کھلی',
    hi: 'खुले',
  );
  static const filterAll = _T(en: 'All', ar: 'الكل', ur: 'سب', hi: 'सभी');
  static const filterFinished = _T(
    en: 'Finished',
    ar: 'منتهية',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const noMatches = _T(
    en: 'No crew requests here.',
    ar: 'لا توجد طلبات طواقم هنا.',
    ur: 'یہاں عملے کی کوئی درخواست نہیں۔',
    hi: 'यहाँ कोई क्रू अनुरोध नहीं।',
  );
  static const stageRequested = _T(
    en: 'Requested',
    ar: 'مطلوب',
    ur: 'درخواست',
    hi: 'अनुरोधित',
  );
  static const stageApproval = _T(
    en: 'Approval',
    ar: 'الاعتماد',
    ur: 'منظوری',
    hi: 'स्वीकृति',
  );
  static const stageAssigning = _T(
    en: 'Workers on site',
    ar: 'العمال في الموقع',
    ur: 'کارکن سائٹ پر',
    hi: 'कामगार साइट पर',
  );
  static const stageDone = _T(
    en: 'Finished',
    ar: 'منتهٍ',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const stageOf = _T(
    en: 'Stage {a} of {b}',
    ar: 'المرحلة {a} من {b}',
    ur: 'مرحلہ {a} از {b}',
    hi: 'चरण {a} / {b}',
  );
  static const progressTitle = _T(
    en: 'Request progress',
    ar: 'تقدم الطلب',
    ur: 'درخواست کی پیش رفت',
    hi: 'अनुरोध की प्रगति',
  );
  static const withLabel = _T(
    en: 'With',
    ar: 'لدى',
    ur: 'کس کے پاس',
    hi: 'किसके पास',
  );
  static const info = _T(
    en: 'Request information',
    ar: 'معلومات الطلب',
    ur: 'درخواست کی معلومات',
    hi: 'अनुरोध जानकारी',
  );
  static const requestInformation = _T(
    en: 'Request information',
    ar: 'معلومات الطلب',
    ur: 'درخواست کی معلومات',
    hi: 'अनुरोध जानकारी',
  );
  static const peopleSection = _T(
    en: 'People needed',
    ar: 'الأشخاص المطلوبون',
    ur: 'درکار افراد',
    hi: 'आवश्यक लोग',
  );
  static const readyToSend = _T(
    en: 'Ready to send',
    ar: 'جاهز للإرسال',
    ur: 'بھیجنے کے لیے تیار',
    hi: 'भेजने के लिए तैयार',
  );
  static const completeBeforeSending = _T(
    en: 'Complete the project, dates and at least one person or trade to send.',
    ar: 'أكمل المشروع والتواريخ وشخصًا أو مهنة واحدة على الأقل للإرسال.',
    ur: 'بھیجنے کے لیے پروجیکٹ، تاریخیں اور کم از کم ایک شخص یا ہنر مکمل کریں۔',
    hi: 'भेजने के लिए प्रोजेक्ट, तारीखें और कम से कम एक व्यक्ति या ट्रेड पूरा करें।',
  );
  static const openAll = _T(
    en: 'Open all crew requests',
    ar: 'فتح كل طلبات الطواقم',
    ur: 'عملے کی تمام درخواستیں کھولیں',
    hi: 'सभी क्रू अनुरोध खोलें',
  );
  static const lineNumber = _T(
    en: 'Line {n}',
    ar: 'البند {n}',
    ur: 'لائن {n}',
    hi: 'पंक्ति {n}',
  );
  static const decideTitle = _T(
    en: 'Review and decide',
    ar: 'المراجعة واتخاذ القرار',
    ur: 'جائزہ لیں اور فیصلہ کریں',
    hi: 'समीक्षा करें और निर्णय लें',
  );
  static const currentOwner = _T(
    en: 'Current owner: {name}',
    ar: 'المسؤول الحالي: {name}',
    ur: 'موجودہ ذمہ دار: {name}',
    hi: 'वर्तमान ज़िम्मेदार: {name}',
  );
  static const assignedPeople = _T(
    en: 'Assigned',
    ar: 'المعيّنون',
    ur: 'مقرر',
    hi: 'सौंपे गए',
  );

  // ─── By name, approve and assign, finish ───────────────────────────────────
  static const stateCompleted = _T(
    en: 'Finished',
    ar: 'منتهٍ',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const nextFinish = _T(
    en: 'Take attendance · finish when the work is done',
    ar: 'سجّل الحضور · أنهِ عند انتهاء العمل',
    ur: 'حاضری لیں · کام ختم ہونے پر مکمل کریں',
    hi: 'हाज़िरी लें · काम पूरा होने पर समाप्त करें',
  );
  static const suggestPeople = _T(
    en: 'People',
    ar: 'الأشخاص',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const suggestTrades = _T(
    en: 'Any worker with this trade',
    ar: 'أي عامل بهذه المهنة',
    ur: 'اس ہنر کا کوئی بھی کارکن',
    hi: 'इस ट्रेड का कोई भी कामगार',
  );
  static const workerFree = _T(en: 'Free', ar: 'متاح', ur: 'فارغ', hi: 'खाली');
  static const workerOnCrew = _T(
    en: 'On {crew}',
    ar: 'في {crew}',
    ur: '{crew} میں',
    hi: '{crew} में',
  );
  static const namedPerson = _T(
    en: 'Asked for by name',
    ar: 'مطلوب بالاسم',
    ur: 'نام سے طلب',
    hi: 'नाम से माँगा',
  );
  static const changePerson = _T(
    en: 'Change',
    ar: 'تغيير',
    ur: 'تبدیل کریں',
    hi: 'बदलें',
  );
  static const onCrewWarningTitle = _T(
    en: '{name} is on {crew}',
    ar: '{name} في {crew}',
    ur: '{name} {crew} میں ہے',
    hi: '{name} {crew} में है',
  );
  static const onCrewWarningBody = _T(
    en: 'The approver sees this. If they approve, {name} moves to this request\'s crew.',
    ar: 'يرى المعتمِد هذا. إذا وافق، ينتقل {name} إلى طاقم هذا الطلب.',
    ur: 'منظور کنندہ یہ دیکھے گا۔ منظوری پر {name} اس درخواست کے عملے میں منتقل ہو جائے گا۔',
    hi: 'स्वीकृतकर्ता यह देखेगा। स्वीकृति पर {name} इस अनुरोध के क्रू में चला जाएगा।',
  );
  static const onCrewApproverWarning = _T(
    en: 'On {crew} · approving moves them here',
    ar: 'في {crew} · الموافقة تنقله إلى هنا',
    ur: '{crew} میں · منظوری انہیں یہاں منتقل کرے گی',
    hi: '{crew} में · स्वीकृति उन्हें यहाँ ले आएगी',
  );
  static const notOnRecords = _T(
    en: 'Not in Worker Records yet? Type the trade instead.',
    ar: 'غير مسجّل في سجلات العمال؟ اكتب المهنة بدلًا من ذلك.',
    ur: 'ورکر ریکارڈ میں نہیں؟ اس کی جگہ ہنر لکھیں۔',
    hi: 'वर्कर रिकॉर्ड में नहीं? इसके बजाय ट्रेड लिखें।',
  );
  static const approveAndAssign = _T(
    en: 'Approve and assign',
    ar: 'وافق وعيّن',
    ur: 'منظور کر کے مقرر کریں',
    hi: 'स्वीकृत करें और सौंपें',
  );
  static const approveOnly = _T(
    en: 'Approve only',
    ar: 'موافقة فقط',
    ur: 'صرف منظور کریں',
    hi: 'केवल स्वीकृत करें',
  );
  static const approveAssignTitle = _T(
    en: 'Approve and assign · {number}',
    ar: 'الموافقة والتعيين · {number}',
    ur: 'منظوری اور تقرری · {number}',
    hi: 'स्वीकृति और सौंपना · {number}',
  );
  static const approveAssignIntro = _T(
    en: 'Approving and assigning in one step. People asked for by name are ticked; untick anyone you do not want, or return the request.',
    ar: 'الموافقة والتعيين في خطوة واحدة. الأشخاص المطلوبون بالاسم محدّدون؛ ألغِ تحديد من لا تريده أو أعد الطلب.',
    ur: 'ایک ہی قدم میں منظوری اور تقرری۔ نام سے طلب کیے گئے افراد منتخب ہیں؛ جسے نہیں چاہتے اس کا نشان ہٹا دیں یا درخواست واپس کریں۔',
    hi: 'एक ही चरण में स्वीकृति और सौंपना। नाम से माँगे गए लोग चुने हुए हैं; जिन्हें नहीं चाहते उनका निशान हटाएँ या अनुरोध वापस करें।',
  );
  static const saveApproveAssign = _T(
    en: 'Approve and assign {n}',
    ar: 'وافق وعيّن {n}',
    ur: 'منظور کر کے {n} مقرر کریں',
    hi: 'स्वीकृत करें और {n} सौंपें',
  );
  static const approvedAssignedToast = _T(
    en: 'Approved · {n} assigned',
    ar: 'تمت الموافقة · عُيّن {n}',
    ur: 'منظور · {n} مقرر',
    hi: 'स्वीकृत · {n} सौंपे',
  );
  static const movesFrom = _T(
    en: 'Moves from {crew}',
    ar: 'ينتقل من {crew}',
    ur: '{crew} سے منتقل ہو گا',
    hi: '{crew} से आएगा',
  );
  static const namedOnLine = _T(
    en: 'Named on this request',
    ar: 'مذكور بالاسم في هذا الطلب',
    ur: 'اس درخواست میں نام سے',
    hi: 'इस अनुरोध में नाम से',
  );
  static const takeAttendance = _T(
    en: 'Take attendance',
    ar: 'تسجيل الحضور',
    ur: 'حاضری لیں',
    hi: 'हाज़िरी लें',
  );
  static const finishRequest = _T(
    en: 'Finish and release workers',
    ar: 'إنهاء وإخلاء العمال',
    ur: 'مکمل کریں اور کارکن فارغ کریں',
    hi: 'समाप्त करें और कामगार मुक्त करें',
  );
  static const finishTitle = _T(
    en: 'Finish {number}?',
    ar: 'إنهاء {number}؟',
    ur: '{number} مکمل کریں؟',
    hi: '{number} समाप्त करें?',
  );
  static const finishBody = _T(
    en: 'The work is done. The workers on this request leave {crew} and are free for other crews. Attendance already taken stays.',
    ar: 'انتهى العمل. يغادر عمال هذا الطلب {crew} ويصبحون متاحين لطواقم أخرى. يبقى الحضور المسجّل.',
    ur: 'کام ختم ہو گیا۔ اس درخواست کے کارکن {crew} چھوڑ دیں گے اور دوسرے عملوں کے لیے فارغ ہوں گے۔ لی گئی حاضری محفوظ رہے گی۔',
    hi: 'काम पूरा हुआ। इस अनुरोध के कामगार {crew} छोड़ देंगे और दूसरे क्रू के लिए खाली होंगे। ली गई हाज़िरी बनी रहेगी।',
  );
  static const finishedToast = _T(
    en: 'Finished · workers released',
    ar: 'انتهى · تم إخلاء العمال',
    ur: 'مکمل · کارکن فارغ',
    hi: 'समाप्त · कामगार मुक्त',
  );
  static const evFinished = _T(
    en: '{name} finished it · {n} released',
    ar: 'أنهاه {name} · أُخلي {n}',
    ur: '{name} نے مکمل کیا · {n} فارغ',
    hi: '{name} ने समाप्त किया · {n} मुक्त',
  );
  static const evMoved = _T(
    en: '{m} moved from another crew',
    ar: 'نُقل {m} من طاقم آخر',
    ur: '{m} دوسرے عملے سے منتقل',
    hi: '{m} दूसरे क्रू से आए',
  );
}
