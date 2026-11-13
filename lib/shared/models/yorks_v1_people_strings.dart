/// People records copy (English, Arabic, Urdu, Hindi).
///
/// Placeholders in braces are filled with [PeopleStrings.t].
library;

import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_attendance_strings.dart';

typedef _T = TranslatableString;

abstract final class PeopleStrings {
  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => AttendanceStrings.t(value, language, v);

  // ─── Centre ────────────────────────────────────────────────────────────────
  static const title = _T(en: 'People', ar: 'الأفراد', ur: 'افراد', hi: 'लोग');
  static const centreDescription = _T(
    en: 'Staff and labour with their visas, passports, labour cards, ILOE, Emirates ID and site passes.',
    ar: 'الموظفون والعمال مع التأشيرات وجوازات السفر وبطاقات العمل والتأمين ضد التعطل والهوية الإماراتية وتصاريح المواقع.',
    ur: 'عملہ اور مزدور، ان کے ویزے، پاسپورٹ، لیبر کارڈ، ILOE، ایمریٹس آئی ڈی اور سائٹ پاس۔',
    hi: 'स्टाफ़ और मज़दूर, उनके वीज़ा, पासपोर्ट, लेबर कार्ड, ILOE, अमीरात आईडी और साइट पास।',
  );
  static const addPerson = _T(
    en: 'Add person',
    ar: 'إضافة شخص',
    ur: 'شخص شامل کریں',
    hi: 'व्यक्ति जोड़ें',
  );
  static const importExcel = _T(
    en: 'Import Excel',
    ar: 'استيراد Excel',
    ur: 'Excel درآمد کریں',
    hi: 'Excel आयात करें',
  );
  static const exportExcel = _T(
    en: 'Export Excel',
    ar: 'تصدير Excel',
    ur: 'Excel برآمد کریں',
    hi: 'Excel निर्यात करें',
  );
  static const refresh = _T(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'تازہ کریں',
    hi: 'रीफ़्रेश करें',
  );
  static const viewAttention = _T(
    en: 'Needs attention',
    ar: 'يحتاج إلى متابعة',
    ur: 'توجہ درکار',
    hi: 'ध्यान चाहिए',
  );
  static const staff = _T(
    en: 'Staff',
    ar: 'الموظفون',
    ur: 'عملہ',
    hi: 'स्टाफ़',
  );
  static const labour = _T(
    en: 'Labour',
    ar: 'العمال',
    ur: 'مزدور',
    hi: 'मज़दूर',
  );
  static const linkWorkforce = _T(
    en: 'Workforce',
    ar: 'القوى العاملة',
    ur: 'افرادی قوت',
    hi: 'कार्यबल',
  );
  static const linkTimesheets = _T(
    en: 'Timesheets',
    ar: 'كشوف الدوام',
    ur: 'ٹائم شیٹس',
    hi: 'टाइमशीट',
  );
  static const kpiTotal = _T(
    en: 'People',
    ar: 'الأفراد',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const kpiTotalHint = _T(
    en: 'Active staff and labour',
    ar: 'الموظفون والعمال النشطون',
    ur: 'فعال عملہ اور مزدور',
    hi: 'सक्रिय स्टाफ़ और मज़दूर',
  );
  static const kpiStaffHint = _T(
    en: 'Office and engineering',
    ar: 'المكتب والهندسة',
    ur: 'دفتر اور انجینئرنگ',
    hi: 'कार्यालय और इंजीनियरिंग',
  );
  static const kpiLabourHint = _T(
    en: 'Site and workshop',
    ar: 'الموقع والورشة',
    ur: 'سائٹ اور ورکشاپ',
    hi: 'साइट और वर्कशॉप',
  );
  static const kpiExpired = _T(
    en: 'Expired',
    ar: 'منتهية',
    ur: 'میعاد ختم',
    hi: 'समाप्त',
  );
  static const kpiExpiredHint = _T(
    en: 'People with an expired document',
    ar: 'أشخاص لديهم مستند منتهٍ',
    ur: 'جن کی کوئی دستاویز ختم ہو چکی',
    hi: 'जिनका कोई दस्तावेज़ समाप्त है',
  );
  static const kpiExpiring = _T(
    en: 'Expiring',
    ar: 'تنتهي قريبًا',
    ur: 'جلد ختم',
    hi: 'जल्द समाप्त',
  );
  static const kpiExpiringHint = _T(
    en: 'Within 60 days',
    ar: 'خلال 60 يومًا',
    ur: '60 دن کے اندر',
    hi: '60 दिनों में',
  );
  static const kpiPasses = _T(
    en: 'Gate passes',
    ar: 'تصاريح البوابات',
    ur: 'گیٹ پاس',
    hi: 'गेट पास',
  );
  static const kpiPassesHint = _T(
    en: 'Expired or expiring',
    ar: 'منتهية أو قريبة الانتهاء',
    ur: 'ختم یا جلد ختم',
    hi: 'समाप्त या जल्द समाप्त',
  );
  static const searchHint = _T(
    en: 'Search names, numbers, companies, documents…',
    ar: 'ابحث في الأسماء والأرقام والشركات والمستندات…',
    ur: 'نام، نمبر، کمپنیاں، دستاویزات تلاش کریں…',
    hi: 'नाम, नंबर, कंपनियाँ, दस्तावेज़ खोजें…',
  );
  static const allCompanies = _T(
    en: 'All companies',
    ar: 'كل الشركات',
    ur: 'تمام کمپنیاں',
    hi: 'सभी कंपनियाँ',
  );
  static const sortName = _T(en: 'Name', ar: 'الاسم', ur: 'نام', hi: 'नाम');
  static const sortExpiry = _T(
    en: 'Soonest expiry',
    ar: 'الأقرب انتهاءً',
    ur: 'جلد ختم ہونے والے',
    hi: 'सबसे पहले समाप्त',
  );
  static const sortCompany = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const colPerson = _T(
    en: 'Person',
    ar: 'الشخص',
    ur: 'شخص',
    hi: 'व्यक्ति',
  );
  static const colCompany = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const colProfession = _T(
    en: 'Profession',
    ar: 'المهنة',
    ur: 'پیشہ',
    hi: 'पेशा',
  );
  static const colPasses = _T(
    en: 'Gate passes',
    ar: 'تصاريح البوابات',
    ur: 'گیٹ پاس',
    hi: 'गेट पास',
  );
  static const emptyRegister = _T(
    en: 'No people match these filters.',
    ar: 'لا يوجد أشخاص مطابقون.',
    ur: 'ان فلٹرز سے کوئی شخص نہیں ملا۔',
    hi: 'इन फ़िल्टर से कोई व्यक्ति नहीं मिला।',
  );
  static const emptyAll = _T(
    en: 'No people yet',
    ar: 'لا يوجد أفراد بعد',
    ur: 'ابھی کوئی شخص نہیں',
    hi: 'अभी कोई व्यक्ति नहीं',
  );
  static const emptyAllBody = _T(
    en: 'Add a person, or import the Staff Documents & Passes tracker.',
    ar: 'أضف شخصًا، أو استورد ملف متابعة مستندات الموظفين والتصاريح.',
    ur: 'کوئی شخص شامل کریں، یا اسٹاف ڈاکیومنٹس اور پاسز ٹریکر درآمد کریں۔',
    hi: 'कोई व्यक्ति जोड़ें, या स्टाफ़ डॉक्यूमेंट्स और पास ट्रैकर आयात करें।',
  );
  static const attentionEmpty = _T(
    en: 'Nothing needs attention',
    ar: 'لا شيء يحتاج إلى متابعة',
    ur: 'کسی چیز پر توجہ درکار نہیں',
    hi: 'किसी पर ध्यान नहीं चाहिए',
  );
  static const attentionEmptyBody = _T(
    en: 'No document has expired or expires in the next 60 days.',
    ar: 'لا يوجد مستند منتهٍ أو ينتهي خلال 60 يومًا.',
    ur: 'کوئی دستاویز ختم نہیں ہوئی اور نہ اگلے 60 دن میں ختم ہو رہی ہے۔',
    hi: 'कोई दस्तावेज़ समाप्त नहीं हुआ और न अगले 60 दिनों में होगा।',
  );
  static const attentionDescription = _T(
    en: 'Expired first, then whatever ends in the next 60 days.',
    ar: 'المنتهية أولًا، ثم ما ينتهي خلال 60 يومًا.',
    ur: 'پہلے ختم شدہ، پھر جو اگلے 60 دن میں ختم ہوں۔',
    hi: 'पहले समाप्त, फिर जो अगले 60 दिनों में समाप्त हों।',
  );
  static const range = _T(
    en: '{a}–{b} of {n}',
    ar: '{a}–{b} من {n}',
    ur: '{n} میں سے {a}–{b}',
    hi: '{n} में से {a}–{b}',
  );
  static const daysLeft = _T(
    en: '{n} days left',
    ar: 'متبقٍ {n} يومًا',
    ur: '{n} دن باقی',
    hi: '{n} दिन शेष',
  );
  static const expiredAgo = _T(
    en: 'Expired {n} days ago',
    ar: 'انتهى منذ {n} يومًا',
    ur: '{n} دن پہلے ختم',
    hi: '{n} दिन पहले समाप्त',
  );
  static const expiresToday = _T(
    en: 'Expires today',
    ar: 'ينتهي اليوم',
    ur: 'آج ختم',
    hi: 'आज समाप्त',
  );
  static const noExpiry = _T(
    en: 'No expiry',
    ar: 'بلا تاريخ انتهاء',
    ur: 'کوئی میعاد نہیں',
    hi: 'कोई समाप्ति नहीं',
  );
  static const notRecorded = _T(
    en: 'Not recorded',
    ar: 'غير مسجّل',
    ur: 'درج نہیں',
    hi: 'दर्ज नहीं',
  );
  static const statusExpired = _T(
    en: 'Expired',
    ar: 'منتهٍ',
    ur: 'ختم',
    hi: 'समाप्त',
  );
  static const statusExpiring = _T(
    en: 'Expiring',
    ar: 'ينتهي قريبًا',
    ur: 'جلد ختم',
    hi: 'जल्द समाप्त',
  );
  static const statusOk = _T(en: 'Valid', ar: 'ساري', ur: 'درست', hi: 'मान्य');
  static const passesCount = _T(
    en: 'Passes: {n}',
    ar: 'التصاريح: {n}',
    ur: 'پاس: {n}',
    hi: 'पास: {n}',
  );
  static const openPerson = _T(
    en: 'Open {name}',
    ar: 'فتح {name}',
    ur: '{name} کھولیں',
    hi: '{name} खोलें',
  );

  // ─── Kinds and categories ──────────────────────────────────────────────────
  static const kindVisa = _T(
    en: 'Visa',
    ar: 'التأشيرة',
    ur: 'ویزا',
    hi: 'वीज़ा',
  );
  static const kindPassport = _T(
    en: 'Passport',
    ar: 'جواز السفر',
    ur: 'پاسپورٹ',
    hi: 'पासपोर्ट',
  );
  static const kindLabourCard = _T(
    en: 'Labour card',
    ar: 'بطاقة العمل',
    ur: 'لیبر کارڈ',
    hi: 'लेबर कार्ड',
  );
  static const kindIloe = _T(en: 'ILOE', ar: 'ILOE', ur: 'ILOE', hi: 'ILOE');
  static const kindEmiratesId = _T(
    en: 'Emirates ID',
    ar: 'الهوية الإماراتية',
    ur: 'ایمریٹس آئی ڈی',
    hi: 'अमीरात आईडी',
  );
  static const kindCicpa = _T(
    en: 'CICPA pass',
    ar: 'تصريح CICPA',
    ur: 'CICPA پاس',
    hi: 'CICPA पास',
  );
  static const kindCmw = _T(
    en: 'CMW pass',
    ar: 'تصريح CMW',
    ur: 'CMW پاس',
    hi: 'CMW पास',
  );
  static const kindOther = _T(
    en: 'Other document',
    ar: 'مستند آخر',
    ur: 'دیگر دستاویز',
    hi: 'अन्य दस्तावेज़',
  );

  // ─── Person record ─────────────────────────────────────────────────────────
  static const personal = _T(
    en: 'Personal details',
    ar: 'البيانات الشخصية',
    ur: 'ذاتی تفصیلات',
    hi: 'व्यक्तिगत विवरण',
  );
  static const documents = _T(
    en: 'Documents',
    ar: 'المستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const documentsDescription = _T(
    en: 'Current documents. A renewal keeps the old one under Previous documents.',
    ar: 'المستندات الحالية. التجديد يحتفظ بالقديم ضمن المستندات السابقة.',
    ur: 'موجودہ دستاویزات۔ تجدید پر پرانی دستاویز سابقہ دستاویزات میں رہتی ہے۔',
    hi: 'वर्तमान दस्तावेज़। नवीनीकरण पर पुराना पिछले दस्तावेज़ों में रहता है।',
  );
  static const previous = _T(
    en: 'Previous documents',
    ar: 'المستندات السابقة',
    ur: 'سابقہ دستاویزات',
    hi: 'पिछले दस्तावेज़',
  );
  static const history = _T(
    en: 'History',
    ar: 'السجل',
    ur: 'تاریخچہ',
    hi: 'इतिहास',
  );
  static const factNumber = _T(
    en: 'Worker number',
    ar: 'رقم العامل',
    ur: 'ورکر نمبر',
    hi: 'कर्मचारी संख्या',
  );
  static const factCategory = _T(
    en: 'Category',
    ar: 'الفئة',
    ur: 'زمرہ',
    hi: 'श्रेणी',
  );
  static const factArabicName = _T(
    en: 'Arabic name',
    ar: 'الاسم بالعربية',
    ur: 'عربی نام',
    hi: 'अरबी नाम',
  );
  static const factDob = _T(
    en: 'Date of birth',
    ar: 'تاريخ الميلاد',
    ur: 'تاریخ پیدائش',
    hi: 'जन्म तिथि',
  );
  static const factUnified = _T(
    en: 'Unified number',
    ar: 'الرقم الموحد',
    ur: 'یونیفائیڈ نمبر',
    hi: 'यूनिफ़ाइड नंबर',
  );
  static const factMobile = _T(
    en: 'Mobile',
    ar: 'الجوال',
    ur: 'موبائل',
    hi: 'मोबाइल',
  );
  static const factJoined = _T(
    en: 'Joined',
    ar: 'تاريخ الالتحاق',
    ur: 'شمولیت',
    hi: 'जुड़े',
  );
  static const factCrew = _T(en: 'Crew', ar: 'الطاقم', ur: 'عملہ', hi: 'क्रू');
  static const factSource = _T(
    en: 'Source',
    ar: 'المصدر',
    ur: 'ماخذ',
    hi: 'स्रोत',
  );
  static const noCrew = _T(
    en: 'Not on a crew',
    ar: 'ليس ضمن طاقم',
    ur: 'کسی عملے میں نہیں',
    hi: 'किसी क्रू में नहीं',
  );
  static const edit = _T(
    en: 'Edit',
    ar: 'تعديل',
    ur: 'ترمیم',
    hi: 'संपादित करें',
  );
  static const addDocument = _T(
    en: 'Add document',
    ar: 'إضافة مستند',
    ur: 'دستاویز شامل کریں',
    hi: 'दस्तावेज़ जोड़ें',
  );
  static const renew = _T(
    en: 'Renew',
    ar: 'تجديد',
    ur: 'تجدید',
    hi: 'नवीनीकरण',
  );
  static const end = _T(
    en: 'End',
    ar: 'إنهاء',
    ur: 'ختم کریں',
    hi: 'समाप्त करें',
  );
  static const add = _T(en: 'Add', ar: 'إضافة', ur: 'شامل کریں', hi: 'जोड़ें');
  static const colDocument = _T(
    en: 'Document',
    ar: 'المستند',
    ur: 'دستاویز',
    hi: 'दस्तावेज़',
  );
  static const colNumber = _T(
    en: 'Number',
    ar: 'الرقم',
    ur: 'نمبر',
    hi: 'नंबर',
  );
  static const colIssue = _T(
    en: 'Issued',
    ar: 'الإصدار',
    ur: 'اجرا',
    hi: 'जारी',
  );
  static const colExpiry = _T(
    en: 'Expiry',
    ar: 'الانتهاء',
    ur: 'میعاد',
    hi: 'समाप्ति',
  );
  static const colStatus = _T(
    en: 'Status',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const colSites = _T(
    en: 'Sites',
    ar: 'المواقع',
    ur: 'سائٹس',
    hi: 'साइटें',
  );
  static const colAction = _T(
    en: 'Action',
    ar: 'الإجراء',
    ur: 'عمل',
    hi: 'कार्रवाई',
  );
  static const allValid = _T(
    en: 'All documents are valid',
    ar: 'كل المستندات سارية',
    ur: 'تمام دستاویزات درست ہیں',
    hi: 'सभी दस्तावेज़ मान्य हैं',
  );
  static const nextExpiry = _T(
    en: 'Next: {doc} on {date}',
    ar: 'التالي: {doc} في {date}',
    ur: 'اگلا: {doc} {date} کو',
    hi: 'अगला: {doc} {date} को',
  );
  static const expiredBanner = _T(
    en: '{doc} expired on {date}',
    ar: 'انتهى {doc} في {date}',
    ur: '{doc} {date} کو ختم ہوا',
    hi: '{doc} {date} को समाप्त हुआ',
  );
  static const expiringBanner = _T(
    en: '{doc} expires on {date}',
    ar: 'ينتهي {doc} في {date}',
    ur: '{doc} {date} کو ختم ہو گا',
    hi: '{doc} {date} को समाप्त होगा',
  );
  static const noDocuments = _T(
    en: 'No documents recorded yet.',
    ar: 'لا توجد مستندات مسجلة بعد.',
    ur: 'ابھی کوئی دستاویز درج نہیں۔',
    hi: 'अभी कोई दस्तावेज़ दर्ज नहीं।',
  );
  static const endedOn = _T(
    en: 'Ended {date} · {reason}',
    ar: 'انتهى {date} · {reason}',
    ur: '{date} کو ختم · {reason}',
    hi: '{date} को समाप्त · {reason}',
  );
  static const renewedReason = _T(
    en: 'renewed',
    ar: 'جُدّد',
    ur: 'تجدید ہوئی',
    hi: 'नवीनीकृत',
  );
  static const hCreated = _T(
    en: '{name} added this person',
    ar: 'أضاف {name} هذا الشخص',
    ur: '{name} نے یہ شخص شامل کیا',
    hi: '{name} ने यह व्यक्ति जोड़ा',
  );
  static const hUpdated = _T(
    en: '{name} edited the details',
    ar: 'عدّل {name} البيانات',
    ur: '{name} نے تفصیلات میں ترمیم کی',
    hi: '{name} ने विवरण संपादित किया',
  );
  static const hDocCreated = _T(
    en: '{name} recorded the {doc}',
    ar: 'سجّل {name} {doc}',
    ur: '{name} نے {doc} درج کیا',
    hi: '{name} ने {doc} दर्ज किया',
  );
  static const hDocUpdated = _T(
    en: '{name} corrected the {doc}',
    ar: 'صحّح {name} {doc}',
    ur: '{name} نے {doc} درست کیا',
    hi: '{name} ने {doc} सुधारा',
  );
  static const hDocRenewed = _T(
    en: '{name} renewed the {doc}',
    ar: 'جدّد {name} {doc}',
    ur: '{name} نے {doc} کی تجدید کی',
    hi: '{name} ने {doc} का नवीनीकरण किया',
  );
  static const hDocEnded = _T(
    en: '{name} ended the {doc}',
    ar: 'أنهى {name} {doc}',
    ur: '{name} نے {doc} ختم کیا',
    hi: '{name} ने {doc} समाप्त किया',
  );
  static const hImported = _T(
    en: '{name} imported from the tracker',
    ar: 'استورد {name} من ملف المتابعة',
    ur: '{name} نے ٹریکر سے درآمد کیا',
    hi: '{name} ने ट्रैकर से आयात किया',
  );
  static const takeAttendance = _T(
    en: 'Take attendance',
    ar: 'تسجيل الحضور',
    ur: 'حاضری لیں',
    hi: 'हाज़िरी लें',
  );

  // ─── Person form ───────────────────────────────────────────────────────────
  static const newPerson = _T(
    en: 'New person',
    ar: 'شخص جديد',
    ur: 'نیا شخص',
    hi: 'नया व्यक्ति',
  );
  static const editPerson = _T(
    en: 'Edit {name}',
    ar: 'تعديل {name}',
    ur: '{name} میں ترمیم',
    hi: '{name} संपादित करें',
  );
  static const formDescription = _T(
    en: 'The person is also a Workforce worker, so crews, attendance and timesheets use the same record.',
    ar: 'الشخص عامل في القوى العاملة أيضًا، فتستخدم الطواقم والحضور وكشوف الدوام السجل نفسه.',
    ur: 'یہ شخص افرادی قوت کا ورکر بھی ہے، اس لیے عملے، حاضری اور ٹائم شیٹس یہی ریکارڈ استعمال کرتے ہیں۔',
    hi: 'यह व्यक्ति कार्यबल का कर्मचारी भी है, इसलिए क्रू, हाज़िरी और टाइमशीट यही रिकॉर्ड उपयोग करते हैं।',
  );
  static const personInformation = _T(
    en: 'Person details',
    ar: 'بيانات الشخص',
    ur: 'شخص کی تفصیلات',
    hi: 'व्यक्ति का विवरण',
  );
  static const personInformationDescription = _T(
    en: 'Name, company and profession appear across Workforce.',
    ar: 'يظهر الاسم والشركة والمهنة في كل أقسام القوى العاملة.',
    ur: 'نام، کمپنی اور پیشہ افرادی قوت میں ہر جگہ نظر آتے ہیں۔',
    hi: 'नाम, कंपनी और पेशा पूरे कार्यबल में दिखते हैं।',
  );
  static const fullName = _T(
    en: 'Full name',
    ar: 'الاسم الكامل',
    ur: 'پورا نام',
    hi: 'पूरा नाम',
  );
  static const arabicName = _T(
    en: 'Arabic name (optional)',
    ar: 'الاسم بالعربية (اختياري)',
    ur: 'عربی نام (اختیاری)',
    hi: 'अरबी नाम (वैकल्पिक)',
  );
  static const company = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const profession = _T(
    en: 'Profession (optional)',
    ar: 'المهنة (اختياري)',
    ur: 'پیشہ (اختیاری)',
    hi: 'पेशा (वैकल्पिक)',
  );
  static const dob = _T(
    en: 'Date of birth (optional)',
    ar: 'تاريخ الميلاد (اختياري)',
    ur: 'تاریخ پیدائش (اختیاری)',
    hi: 'जन्म तिथि (वैकल्पिक)',
  );
  static const unified = _T(
    en: 'Unified number (optional)',
    ar: 'الرقم الموحد (اختياري)',
    ur: 'یونیفائیڈ نمبر (اختیاری)',
    hi: 'यूनिफ़ाइड नंबर (वैकल्पिक)',
  );
  static const mobile = _T(
    en: 'Mobile (optional)',
    ar: 'الجوال (اختياري)',
    ur: 'موبائل (اختیاری)',
    hi: 'मोबाइल (वैकल्पिक)',
  );
  static const save = _T(en: 'Save', ar: 'حفظ', ur: 'محفوظ کریں', hi: 'सहेजें');
  static const cancel = _T(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ',
    hi: 'रद्द करें',
  );
  static const saving = _T(
    en: 'Saving…',
    ar: 'جارٍ الحفظ…',
    ur: 'محفوظ ہو رہا ہے…',
    hi: 'सहेजा जा रहा है…',
  );
  static const clear = _T(
    en: 'Clear',
    ar: 'مسح',
    ur: 'صاف کریں',
    hi: 'साफ़ करें',
  );
  static const errName = _T(
    en: 'Enter the full name.',
    ar: 'أدخل الاسم الكامل.',
    ur: 'پورا نام درج کریں۔',
    hi: 'पूरा नाम दर्ज करें।',
  );
  static const errCompany = _T(
    en: 'Enter the company.',
    ar: 'أدخل الشركة.',
    ur: 'کمپنی درج کریں۔',
    hi: 'कंपनी दर्ज करें।',
  );
  static const savedToast = _T(
    en: '{name} saved',
    ar: 'تم حفظ {name}',
    ur: '{name} محفوظ ہو گیا',
    hi: '{name} सहेजा गया',
  );

  // ─── Document dialog ───────────────────────────────────────────────────────
  static const addDocumentTitle = _T(
    en: 'Add document',
    ar: 'إضافة مستند',
    ur: 'دستاویز شامل کریں',
    hi: 'दस्तावेज़ जोड़ें',
  );
  static const editDocumentTitle = _T(
    en: 'Edit {doc}',
    ar: 'تعديل {doc}',
    ur: '{doc} میں ترمیم',
    hi: '{doc} संपादित करें',
  );
  static const renewDocumentTitle = _T(
    en: 'Renew {doc}',
    ar: 'تجديد {doc}',
    ur: '{doc} کی تجدید',
    hi: '{doc} का नवीनीकरण',
  );
  static const renewHint = _T(
    en: 'The current {doc} moves to Previous documents.',
    ar: 'ينتقل {doc} الحالي إلى المستندات السابقة.',
    ur: 'موجودہ {doc} سابقہ دستاویزات میں چلا جائے گا۔',
    hi: 'वर्तमान {doc} पिछले दस्तावेज़ों में चला जाएगा।',
  );
  static const documentKind = _T(
    en: 'Document',
    ar: 'المستند',
    ur: 'دستاویز',
    hi: 'दस्तावेज़',
  );
  static const documentLabel = _T(
    en: 'Name of the document',
    ar: 'اسم المستند',
    ur: 'دستاویز کا نام',
    hi: 'दस्तावेज़ का नाम',
  );
  static const documentNumber = _T(
    en: 'Number (optional)',
    ar: 'الرقم (اختياري)',
    ur: 'نمبر (اختیاری)',
    hi: 'नंबर (वैकल्पिक)',
  );
  static const issueDate = _T(
    en: 'Issue date (optional)',
    ar: 'تاريخ الإصدار (اختياري)',
    ur: 'تاریخ اجرا (اختیاری)',
    hi: 'जारी करने की तिथि (वैकल्पिक)',
  );
  static const expiryDate = _T(
    en: 'Expiry date',
    ar: 'تاريخ الانتهاء',
    ur: 'تاریخ اختتام',
    hi: 'समाप्ति तिथि',
  );
  static const sites = _T(
    en: 'Sites (optional)',
    ar: 'المواقع (اختياري)',
    ur: 'سائٹس (اختیاری)',
    hi: 'साइटें (वैकल्पिक)',
  );
  static const notes = _T(
    en: 'Notes (optional)',
    ar: 'ملاحظات (اختياري)',
    ur: 'نوٹس (اختیاری)',
    hi: 'टिप्पणियाँ (वैकल्पिक)',
  );
  static const errDocValue = _T(
    en: 'Enter a number or an expiry date.',
    ar: 'أدخل رقمًا أو تاريخ انتهاء.',
    ur: 'نمبر یا تاریخ اختتام درج کریں۔',
    hi: 'नंबर या समाप्ति तिथि दर्ज करें।',
  );
  static const errDocDates = _T(
    en: 'The expiry is before the issue date.',
    ar: 'تاريخ الانتهاء قبل تاريخ الإصدار.',
    ur: 'تاریخ اختتام اجرا سے پہلے ہے۔',
    hi: 'समाप्ति तिथि जारी तिथि से पहले है।',
  );
  static const errLabel = _T(
    en: 'Name the document.',
    ar: 'اكتب اسم المستند.',
    ur: 'دستاویز کا نام لکھیں۔',
    hi: 'दस्तावेज़ का नाम लिखें।',
  );
  static const errExists = _T(
    en: 'This person already has a current {doc}. Renew it instead.',
    ar: 'لدى هذا الشخص {doc} حالي. جدّده بدلًا من ذلك.',
    ur: 'اس شخص کا موجودہ {doc} پہلے سے ہے۔ اس کی تجدید کریں۔',
    hi: 'इस व्यक्ति का वर्तमान {doc} पहले से है। उसका नवीनीकरण करें।',
  );
  static const endTitle = _T(
    en: 'End {doc}?',
    ar: 'إنهاء {doc}؟',
    ur: '{doc} ختم کریں؟',
    hi: '{doc} समाप्त करें?',
  );
  static const endBody = _T(
    en: 'It moves to Previous documents. Use this when it was cancelled or handed back.',
    ar: 'ينتقل إلى المستندات السابقة. استخدم هذا عند إلغائه أو تسليمه.',
    ur: 'یہ سابقہ دستاویزات میں چلا جائے گا۔ منسوخ یا واپس ہونے پر استعمال کریں۔',
    hi: 'यह पिछले दस्तावेज़ों में चला जाएगा। रद्द या लौटाए जाने पर उपयोग करें।',
  );
  static const reason = _T(en: 'Reason', ar: 'السبب', ur: 'وجہ', hi: 'कारण');
  static const endedToast = _T(
    en: '{doc} ended',
    ar: 'انتهى {doc}',
    ur: '{doc} ختم',
    hi: '{doc} समाप्त',
  );
  static const savedDocToast = _T(
    en: '{doc} saved',
    ar: 'تم حفظ {doc}',
    ur: '{doc} محفوظ',
    hi: '{doc} सहेजा गया',
  );
  static const renewedToast = _T(
    en: '{doc} renewed',
    ar: 'تم تجديد {doc}',
    ur: '{doc} کی تجدید ہو گئی',
    hi: '{doc} नवीनीकृत',
  );

  // ─── Import and export ─────────────────────────────────────────────────────
  static const importIntro = _T(
    en: 'Choose the Staff Documents & Passes tracker. Nothing changes until you press Import.',
    ar: 'اختر ملف متابعة مستندات الموظفين والتصاريح. لن يتغير شيء حتى تضغط استيراد.',
    ur: 'اسٹاف ڈاکیومنٹس اور پاسز ٹریکر چنیں۔ درآمد دبانے تک کچھ نہیں بدلے گا۔',
    hi: 'स्टाफ़ डॉक्यूमेंट्स और पास ट्रैकर चुनें। आयात दबाने तक कुछ नहीं बदलेगा।',
  );
  static const chooseFile = _T(
    en: 'Choose file',
    ar: 'اختيار ملف',
    ur: 'فائل چنیں',
    hi: 'फ़ाइल चुनें',
  );
  static const reading = _T(
    en: 'Reading the file…',
    ar: 'جارٍ قراءة الملف…',
    ur: 'فائل پڑھی جا رہی ہے…',
    hi: 'फ़ाइल पढ़ी जा रही है…',
  );
  static const checking = _T(
    en: 'Checking with the server…',
    ar: 'جارٍ التحقق مع الخادم…',
    ur: 'سرور سے جانچ ہو رہی ہے…',
    hi: 'सर्वर से जाँच हो रही है…',
  );
  static const readPeople = _T(
    en: '{n} people found: {s} staff, {l} labour',
    ar: 'تم العثور على {n} شخصًا: {s} موظفًا و{l} عاملًا',
    ur: '{n} افراد ملے: {s} عملہ، {l} مزدور',
    hi: '{n} लोग मिले: {s} स्टाफ़, {l} मज़दूर',
  );
  static const readPasses = _T(
    en: '{n} gate passes joined to people',
    ar: 'تم ربط {n} تصريح بوابة بالأشخاص',
    ur: '{n} گیٹ پاس افراد سے جوڑے گئے',
    hi: '{n} गेट पास लोगों से जोड़े गए',
  );
  static const readAdded = _T(
    en: '{n} people added from the gate pass list',
    ar: 'تمت إضافة {n} شخصًا من قائمة تصاريح البوابات',
    ur: 'گیٹ پاس فہرست سے {n} افراد شامل کیے گئے',
    hi: 'गेट पास सूची से {n} लोग जोड़े गए',
  );
  static const readSkipped = _T(
    en: '{n} insurance lines skipped (company documents)',
    ar: 'تم تخطي {n} من بنود التأمين (مستندات الشركة)',
    ur: '{n} انشورنس لائنیں چھوڑی گئیں (کمپنی دستاویزات)',
    hi: '{n} बीमा पंक्तियाँ छोड़ी गईं (कंपनी दस्तावेज़)',
  );
  static const readVehicles = _T(
    en: '{n} vehicle passes kept for company documents',
    ar: 'تم الاحتفاظ بـ {n} تصريح مركبة لمستندات الشركة',
    ur: '{n} گاڑیوں کے پاس کمپنی دستاویزات کے لیے رکھے گئے',
    hi: '{n} वाहन पास कंपनी दस्तावेज़ों के लिए रखे गए',
  );
  static const readIssues = _T(
    en: '{n} cells could not be read',
    ar: 'تعذّرت قراءة {n} خلية',
    ur: '{n} خانے پڑھے نہ جا سکے',
    hi: '{n} सेल पढ़े नहीं जा सके',
  );
  static const pNew = _T(en: 'New', ar: 'جديد', ur: 'نئے', hi: 'नए');
  static const pUpdate = _T(
    en: 'Updated',
    ar: 'محدَّث',
    ur: 'تازہ کردہ',
    hi: 'अपडेट',
  );
  static const pUnchanged = _T(
    en: 'Unchanged',
    ar: 'بلا تغيير',
    ur: 'بلا تبدیلی',
    hi: 'अपरिवर्तित',
  );
  static const pProblem = _T(
    en: 'Problems',
    ar: 'مشكلات',
    ur: 'مسائل',
    hi: 'समस्याएँ',
  );
  static const docsSummary = _T(
    en: 'Documents: {a} added, {r} renewed, {u} corrected',
    ar: 'المستندات: {a} مضافة، {r} مجدَّدة، {u} مصحَّحة',
    ur: 'دستاویزات: {a} شامل، {r} تجدید، {u} درست',
    hi: 'दस्तावेज़: {a} जोड़े, {r} नवीनीकृत, {u} सुधारे',
  );
  static const colRow = _T(en: 'Row', ar: 'الصف', ur: 'قطار', hi: 'पंक्ति');
  static const colChanges = _T(
    en: 'What changes',
    ar: 'ما يتغير',
    ur: 'کیا بدلے گا',
    hi: 'क्या बदलेगा',
  );
  static const probName = _T(
    en: 'Name missing',
    ar: 'الاسم مفقود',
    ur: 'نام موجود نہیں',
    hi: 'नाम नहीं है',
  );
  static const probCompany = _T(
    en: 'Company missing',
    ar: 'الشركة مفقودة',
    ur: 'کمپنی موجود نہیں',
    hi: 'कंपनी नहीं है',
  );
  static const probRepeated = _T(
    en: 'Repeated in the file',
    ar: 'مكرر في الملف',
    ur: 'فائل میں دہرایا گیا',
    hi: 'फ़ाइल में दोहराया गया',
  );
  static const probAmbiguous = _T(
    en: 'Matches two saved people',
    ar: 'يطابق شخصين محفوظين',
    ur: 'دو محفوظ افراد سے ملتا ہے',
    hi: 'दो सहेजे गए लोगों से मेल खाता है',
  );
  static const probDate = _T(
    en: 'A date is not a date',
    ar: 'تاريخ غير صالح',
    ur: 'ایک تاریخ درست نہیں',
    hi: 'एक तिथि मान्य नहीं',
  );
  static const probDocument = _T(
    en: 'A document cell could not be read',
    ar: 'تعذّرت قراءة خلية مستند',
    ur: 'دستاویز کا خانہ پڑھا نہ جا سکا',
    hi: 'दस्तावेज़ सेल पढ़ा नहीं जा सका',
  );
  static const importAction = _T(
    en: 'Import',
    ar: 'استيراد',
    ur: 'درآمد کریں',
    hi: 'आयात करें',
  );
  static const importing = _T(
    en: 'Importing…',
    ar: 'جارٍ الاستيراد…',
    ur: 'درآمد ہو رہا ہے…',
    hi: 'आयात हो रहा है…',
  );
  static const importDone = _T(
    en: 'Imported: {n} new, {u} updated',
    ar: 'تم الاستيراد: {n} جديد، {u} محدَّث',
    ur: 'درآمد مکمل: {n} نئے، {u} تازہ',
    hi: 'आयात हुआ: {n} नए, {u} अपडेट',
  );
  static const importBlocked = _T(
    en: 'Fix the rows with problems in the file, then choose it again.',
    ar: 'أصلح الصفوف ذات المشكلات في الملف ثم اختره مجددًا.',
    ur: 'فائل میں مسائل والی قطاریں درست کریں، پھر دوبارہ چنیں۔',
    hi: 'फ़ाइल में समस्या वाली पंक्तियाँ ठीक करें, फिर दोबारा चुनें।',
  );
  static const importNothing = _T(
    en: 'Everything in the file is already recorded.',
    ar: 'كل ما في الملف مسجَّل بالفعل.',
    ur: 'فائل میں سب کچھ پہلے سے درج ہے۔',
    hi: 'फ़ाइल में सब कुछ पहले से दर्ज है।',
  );
  static const noStaffSheet = _T(
    en: 'No staff sheet was found. Use the Staff Documents & Passes tracker, or an export from here.',
    ar: 'لم يتم العثور على ورقة الموظفين. استخدم ملف المتابعة أو ملفًا مصدَّرًا من هنا.',
    ur: 'اسٹاف شیٹ نہیں ملی۔ ٹریکر یا یہاں سے برآمد کی گئی فائل استعمال کریں۔',
    hi: 'स्टाफ़ शीट नहीं मिली। ट्रैकर या यहाँ से निर्यात की गई फ़ाइल उपयोग करें।',
  );
  static const fromPasses = _T(
    en: 'From gate passes',
    ar: 'من تصاريح البوابات',
    ur: 'گیٹ پاس سے',
    hi: 'गेट पास से',
  );
  static const exportDone = _T(
    en: 'Exported {n} people',
    ar: 'تم تصدير {n} شخصًا',
    ur: '{n} افراد برآمد ہوئے',
    hi: '{n} लोग निर्यात हुए',
  );

  // ─── Errors ────────────────────────────────────────────────────────────────
  static const errOffline = _T(
    en: 'You are offline. Connect and try again.',
    ar: 'أنت غير متصل. اتصل وحاول مجددًا.',
    ur: 'آپ آف لائن ہیں۔ جڑیں اور دوبارہ کوشش کریں۔',
    hi: 'आप ऑफ़लाइन हैं। कनेक्ट करके फिर कोशिश करें।',
  );
  static const errDenied = _T(
    en: 'You do not have access to people records.',
    ar: 'ليس لديك صلاحية على سجلات الأفراد.',
    ur: 'آپ کو افراد کے ریکارڈ تک رسائی نہیں۔',
    hi: 'आपको लोगों के रिकॉर्ड तक पहुँच नहीं है।',
  );
  static const errConflict = _T(
    en: 'Someone else changed this. Refresh and try again.',
    ar: 'غيّر شخص آخر هذا. حدّث وحاول مجددًا.',
    ur: 'کسی اور نے یہ بدل دیا۔ تازہ کر کے دوبارہ کوشش کریں۔',
    hi: 'किसी और ने इसे बदल दिया। रीफ़्रेश करके फिर कोशिश करें।',
  );
  static const errInvalid = _T(
    en: 'Some details are not valid. Check them and try again.',
    ar: 'بعض البيانات غير صالحة. تحقق منها وحاول مجددًا.',
    ur: 'کچھ تفصیلات درست نہیں۔ جانچ کر دوبارہ کوشش کریں۔',
    hi: 'कुछ विवरण मान्य नहीं। जाँचकर फिर कोशिश करें।',
  );
  static const errGeneric = _T(
    en: 'Something went wrong. Try again.',
    ar: 'حدث خطأ. حاول مجددًا.',
    ur: 'کچھ غلط ہو گیا۔ دوبارہ کوشش کریں۔',
    hi: 'कुछ गलत हो गया। फिर कोशिश करें।',
  );
  static const retry = _T(
    en: 'Try again',
    ar: 'حاول مجددًا',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर कोशिश करें',
  );
}
