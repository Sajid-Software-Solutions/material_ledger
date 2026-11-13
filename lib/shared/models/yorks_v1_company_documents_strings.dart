/// Company documents copy (English, Arabic, Urdu, Hindi). Wording shared
/// with People (dates, statuses, document fields) lives in [PeopleStrings].
///
/// Placeholders in braces are filled with [CompanyStrings.t].
library;

import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_attendance_strings.dart';

typedef _T = TranslatableString;

abstract final class CompanyStrings {
  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => AttendanceStrings.t(value, language, v);

  // ─── Home ──────────────────────────────────────────────────────────────────
  static const title = _T(
    en: 'Company documents',
    ar: 'مستندات الشركة',
    ur: 'کمپنی کی دستاویزات',
    hi: 'कंपनी दस्तावेज़',
  );
  static const centreDescription = _T(
    en: 'Trade licences, permits, certificates, vehicles, insurance and CICPA contracts for every company and branch.',
    ar: 'الرخص التجارية والتصاريح والشهادات والمركبات والتأمين وعقود CICPA لكل شركة وفرع.',
    ur: 'ہر کمپنی اور برانچ کے تجارتی لائسنس، پرمٹ، سرٹیفکیٹ، گاڑیاں، انشورنس اور CICPA معاہدے۔',
    hi: 'हर कंपनी और शाखा के ट्रेड लाइसेंस, परमिट, प्रमाणपत्र, वाहन, बीमा और CICPA अनुबंध।',
  );
  static const addRecord = _T(
    en: 'Add record',
    ar: 'إضافة سجل',
    ur: 'ریکارڈ شامل کریں',
    hi: 'रिकॉर्ड जोड़ें',
  );
  static const viewLicences = _T(
    en: 'Licences & permits',
    ar: 'الرخص والتصاريح',
    ur: 'لائسنس اور پرمٹ',
    hi: 'लाइसेंस और परमिट',
  );
  static const viewVehicles = _T(
    en: 'Vehicles',
    ar: 'المركبات',
    ur: 'گاڑیاں',
    hi: 'वाहन',
  );
  static const viewInsurance = _T(
    en: 'Insurance',
    ar: 'التأمين',
    ur: 'انشورنس',
    hi: 'बीमा',
  );
  static const viewContracts = _T(
    en: 'CICPA contracts',
    ar: 'عقود CICPA',
    ur: 'CICPA معاہدے',
    hi: 'CICPA अनुबंध',
  );
  static const linkPeople = _T(
    en: 'People',
    ar: 'الأفراد',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const kpiRecords = _T(
    en: 'Records',
    ar: 'السجلات',
    ur: 'ریکارڈ',
    hi: 'रिकॉर्ड',
  );
  static const kpiRecordsHint = _T(
    en: 'Everything tracked',
    ar: 'كل ما تتم متابعته',
    ur: 'ہر وہ چیز جس کی نگرانی ہوتی ہے',
    hi: 'जो कुछ ट्रैक होता है',
  );
  static const kpiLicencesHint = _T(
    en: '{e} companies · {i} certificates',
    ar: '{e} شركات · {i} شهادات',
    ur: '{e} کمپنیاں · {i} سرٹیفکیٹ',
    hi: '{e} कंपनियाँ · {i} प्रमाणपत्र',
  );
  static const kpiVehiclesHint = _T(
    en: 'Registrations, Asateel and passes',
    ar: 'التسجيل وأساطيل والتصاريح',
    ur: 'رجسٹریشن، اساطیل اور پاس',
    hi: 'पंजीकरण, असातील और पास',
  );
  static const kpiCover = _T(
    en: 'Insurance & contracts',
    ar: 'التأمين والعقود',
    ur: 'انشورنس اور معاہدے',
    hi: 'बीमा और अनुबंध',
  );
  static const kpiCoverHint = _T(
    en: '{p} policies · {c} contracts',
    ar: '{p} وثائق · {c} عقود',
    ur: '{p} پالیسیاں · {c} معاہدے',
    hi: '{p} पॉलिसी · {c} अनुबंध',
  );
  static const kpiExpiredHint = _T(
    en: 'Records with an expired document',
    ar: 'سجلات بها مستند منتهٍ',
    ur: 'جن ریکارڈ کی کوئی دستاویز ختم ہو چکی',
    hi: 'जिन रिकॉर्ड का कोई दस्तावेज़ समाप्त है',
  );
  static const searchHint = _T(
    en: 'Search names, numbers, plates, LOAs, companies…',
    ar: 'ابحث في الأسماء والأرقام واللوحات وأرقام LOA والشركات…',
    ur: 'نام، نمبر، پلیٹ، LOA، کمپنیاں تلاش کریں…',
    hi: 'नाम, नंबर, प्लेट, LOA, कंपनियाँ खोजें…',
  );
  static const showArchived = _T(
    en: 'Show archived',
    ar: 'إظهار المؤرشف',
    ur: 'محفوظ شدہ دکھائیں',
    hi: 'संग्रहित दिखाएँ',
  );
  static const colRecord = _T(
    en: 'Record',
    ar: 'السجل',
    ur: 'ریکارڈ',
    hi: 'रिकॉर्ड',
  );
  static const colReference = _T(
    en: 'Reference',
    ar: 'المرجع',
    ur: 'حوالہ',
    hi: 'संदर्भ',
  );
  static const colOwner = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const colDocuments = _T(
    en: 'Documents',
    ar: 'المستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const colNextExpiry = _T(
    en: 'Next expiry',
    ar: 'أقرب انتهاء',
    ur: 'اگلی میعاد',
    hi: 'अगली समाप्ति',
  );
  static const documentsCount = _T(
    en: '{n} documents',
    ar: '{n} مستندات',
    ur: '{n} دستاویزات',
    hi: '{n} दस्तावेज़',
  );
  static const emptyAll = _T(
    en: 'No company records yet',
    ar: 'لا توجد سجلات للشركة بعد',
    ur: 'ابھی کمپنی کا کوئی ریکارڈ نہیں',
    hi: 'अभी कंपनी का कोई रिकॉर्ड नहीं',
  );
  static const emptyAllBody = _T(
    en: 'Add a record, or import the Staff Documents & Passes tracker.',
    ar: 'أضف سجلًا، أو استورد ملف متابعة المستندات والتصاريح.',
    ur: 'ریکارڈ شامل کریں، یا اسٹاف ڈاکیومنٹس اور پاسز ٹریکر درآمد کریں۔',
    hi: 'रिकॉर्ड जोड़ें, या स्टाफ़ डॉक्यूमेंट्स और पास ट्रैकर आयात करें।',
  );
  static const emptyRegister = _T(
    en: 'No records match these filters.',
    ar: 'لا توجد سجلات مطابقة.',
    ur: 'ان فلٹرز سے کوئی ریکارڈ نہیں ملا۔',
    hi: 'इन फ़िल्टर से कोई रिकॉर्ड नहीं मिला।',
  );
  static const noDocumentsYet = _T(
    en: 'No document recorded',
    ar: 'لا يوجد مستند مسجل',
    ur: 'کوئی دستاویز درج نہیں',
    hi: 'कोई दस्तावेज़ दर्ज नहीं',
  );

  // ─── Kinds ─────────────────────────────────────────────────────────────────
  static const kindEntity = _T(
    en: 'Company or branch',
    ar: 'شركة أو فرع',
    ur: 'کمپنی یا برانچ',
    hi: 'कंपनी या शाखा',
  );
  static const kindItem = _T(
    en: 'Certificate or permit',
    ar: 'شهادة أو تصريح',
    ur: 'سرٹیفکیٹ یا پرمٹ',
    hi: 'प्रमाणपत्र या परमिट',
  );
  static const kindVehicle = _T(
    en: 'Vehicle',
    ar: 'مركبة',
    ur: 'گاڑی',
    hi: 'वाहन',
  );
  static const kindPolicy = _T(
    en: 'Insurance policy',
    ar: 'وثيقة تأمين',
    ur: 'انشورنس پالیسی',
    hi: 'बीमा पॉलिसी',
  );
  static const kindContract = _T(
    en: 'CICPA contract',
    ar: 'عقد CICPA',
    ur: 'CICPA معاہدہ',
    hi: 'CICPA अनुबंध',
  );
  static const docLicence = _T(
    en: 'Trade licence',
    ar: 'الرخصة التجارية',
    ur: 'تجارتی لائسنس',
    hi: 'ट्रेड लाइसेंस',
  );
  static const docEstablishment = _T(
    en: 'Establishment card',
    ar: 'بطاقة المنشأة',
    ur: 'اسٹیبلشمنٹ کارڈ',
    hi: 'एस्टैब्लिशमेंट कार्ड',
  );
  static const docLabourFile = _T(
    en: 'Labour file',
    ar: 'ملف العمل',
    ur: 'لیبر فائل',
    hi: 'लेबर फ़ाइल',
  );
  static const docProCard = _T(
    en: 'PRO card',
    ar: 'بطاقة المندوب',
    ur: 'پی آر او کارڈ',
    hi: 'पीआरओ कार्ड',
  );
  static const docRegistration = _T(
    en: 'Registration',
    ar: 'تسجيل المركبة',
    ur: 'رجسٹریشن',
    hi: 'पंजीकरण',
  );
  static const docAsateel = _T(
    en: 'Asateel permit',
    ar: 'تصريح أساطيل',
    ur: 'اساطیل پرمٹ',
    hi: 'असातील परमिट',
  );
  static const docCicpa = _T(
    en: 'CICPA pass',
    ar: 'تصريح CICPA',
    ur: 'CICPA پاس',
    hi: 'CICPA पास',
  );
  static const docInsurance = _T(
    en: 'Insurance',
    ar: 'التأمين',
    ur: 'انشورنس',
    hi: 'बीमा',
  );
  static const docContract = _T(en: 'LOA', ar: 'LOA', ur: 'LOA', hi: 'LOA');
  static const docCertificate = _T(
    en: 'Certificate or permit',
    ar: 'شهادة أو تصريح',
    ur: 'سرٹیفکیٹ یا پرمٹ',
    hi: 'प्रमाणपत्र या परमिट',
  );
  static const docOther = _T(
    en: 'Other document',
    ar: 'مستند آخر',
    ur: 'دیگر دستاویز',
    hi: 'अन्य दस्तावेज़',
  );

  // ─── Record ────────────────────────────────────────────────────────────────
  static const details = _T(
    en: 'Details',
    ar: 'التفاصيل',
    ur: 'تفصیلات',
    hi: 'विवरण',
  );
  static const refLicence = _T(
    en: 'Licence number',
    ar: 'رقم الرخصة',
    ur: 'لائسنس نمبر',
    hi: 'लाइसेंस नंबर',
  );
  static const refPlate = _T(
    en: 'Plate',
    ar: 'رقم اللوحة',
    ur: 'نمبر پلیٹ',
    hi: 'प्लेट',
  );
  static const refPolicy = _T(
    en: 'Policy number',
    ar: 'رقم الوثيقة',
    ur: 'پالیسی نمبر',
    hi: 'पॉलिसी नंबर',
  );
  static const refLoa = _T(
    en: 'LOA number',
    ar: 'رقم LOA',
    ur: 'LOA نمبر',
    hi: 'LOA नंबर',
  );
  static const refOther = _T(
    en: 'Reference',
    ar: 'المرجع',
    ur: 'حوالہ',
    hi: 'संदर्भ',
  );
  static const owner = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const ownerVehicle = _T(
    en: 'Owner',
    ar: 'المالك',
    ur: 'مالک',
    hi: 'मालिक',
  );
  static const job = _T(en: 'Job', ar: 'المشروع', ur: 'کام', hi: 'काम');
  static const people = _T(en: 'People', ar: 'الأفراد', ur: 'افراد', hi: 'लोग');
  static const vehicles = _T(
    en: 'Vehicles',
    ar: 'المركبات',
    ur: 'گاڑیاں',
    hi: 'वाहन',
  );
  static const appliedPeople = _T(
    en: 'People passes applied',
    ar: 'تصاريح الأفراد المقدمة',
    ur: 'افراد کے پاس کی درخواست',
    hi: 'लोगों के पास के आवेदन',
  );
  static const appliedVehicles = _T(
    en: 'Vehicle passes applied',
    ar: 'تصاريح المركبات المقدمة',
    ur: 'گاڑیوں کے پاس کی درخواست',
    hi: 'वाहन पास के आवेदन',
  );
  static const notes = _T(
    en: 'Notes',
    ar: 'ملاحظات',
    ur: 'نوٹس',
    hi: 'टिप्पणियाँ',
  );
  static const archive = _T(
    en: 'Archive',
    ar: 'أرشفة',
    ur: 'محفوظ کریں',
    hi: 'संग्रहित करें',
  );
  static const restore = _T(
    en: 'Restore',
    ar: 'استعادة',
    ur: 'بحال کریں',
    hi: 'पुनर्स्थापित करें',
  );
  static const archiveTitle = _T(
    en: 'Archive {name}?',
    ar: 'أرشفة {name}؟',
    ur: '{name} محفوظ کریں؟',
    hi: '{name} संग्रहित करें?',
  );
  static const archiveBody = _T(
    en: 'It leaves the registers and keeps every document and its history. Use this for a sold vehicle or a finished contract.',
    ar: 'يخرج من السجلات ويحتفظ بكل مستند وسجله. استخدم هذا لمركبة مباعة أو عقد منتهٍ.',
    ur: 'یہ رجسٹر سے نکل جائے گا اور ہر دستاویز اور اس کی تاریخ محفوظ رہے گی۔ بیچی گئی گاڑی یا ختم شدہ معاہدے کے لیے استعمال کریں۔',
    hi: 'यह रजिस्टर से हट जाएगा और हर दस्तावेज़ व उसका इतिहास रहेगा। बेचे गए वाहन या समाप्त अनुबंध के लिए उपयोग करें।',
  );
  static const archivedToast = _T(
    en: '{name} archived',
    ar: 'تمت أرشفة {name}',
    ur: '{name} محفوظ ہو گیا',
    hi: '{name} संग्रहित',
  );
  static const restoredToast = _T(
    en: '{name} restored',
    ar: 'تمت استعادة {name}',
    ur: '{name} بحال ہو گیا',
    hi: '{name} पुनर्स्थापित',
  );
  static const archivedBanner = _T(
    en: 'Archived {date} · {reason}',
    ar: 'مؤرشف {date} · {reason}',
    ur: '{date} کو محفوظ · {reason}',
    hi: '{date} को संग्रहित · {reason}',
  );
  static const hCreated = _T(
    en: '{name} added this record',
    ar: 'أضاف {name} هذا السجل',
    ur: '{name} نے یہ ریکارڈ شامل کیا',
    hi: '{name} ने यह रिकॉर्ड जोड़ा',
  );
  static const hArchived = _T(
    en: '{name} archived the record',
    ar: 'أرشف {name} السجل',
    ur: '{name} نے ریکارڈ محفوظ کیا',
    hi: '{name} ने रिकॉर्ड संग्रहित किया',
  );
  static const hRestored = _T(
    en: '{name} restored the record',
    ar: 'استعاد {name} السجل',
    ur: '{name} نے ریکارڈ بحال کیا',
    hi: '{name} ने रिकॉर्ड पुनर्स्थापित किया',
  );

  // ─── Form ──────────────────────────────────────────────────────────────────
  static const newRecord = _T(
    en: 'New record',
    ar: 'سجل جديد',
    ur: 'نیا ریکارڈ',
    hi: 'नया रिकॉर्ड',
  );
  static const editRecord = _T(
    en: 'Edit {name}',
    ar: 'تعديل {name}',
    ur: '{name} میں ترمیم',
    hi: '{name} संपादित करें',
  );
  static const formDescription = _T(
    en: 'A record holds its documents. Save it, then record its licence, registration, pass or policy.',
    ar: 'يحتوي السجل على مستنداته. احفظه ثم سجّل الرخصة أو التسجيل أو التصريح أو الوثيقة.',
    ur: 'ریکارڈ میں اس کی دستاویزات ہوتی ہیں۔ اسے محفوظ کریں، پھر لائسنس، رجسٹریشن، پاس یا پالیسی درج کریں۔',
    hi: 'रिकॉर्ड में उसके दस्तावेज़ होते हैं। इसे सहेजें, फिर लाइसेंस, पंजीकरण, पास या पॉलिसी दर्ज करें।',
  );
  static const recordInformation = _T(
    en: 'Record details',
    ar: 'بيانات السجل',
    ur: 'ریکارڈ کی تفصیلات',
    hi: 'रिकॉर्ड का विवरण',
  );
  static const recordInformationDescription = _T(
    en: 'What it is, its number and the company it belongs to.',
    ar: 'ما هو، ورقمه، والشركة التابع لها.',
    ur: 'یہ کیا ہے، اس کا نمبر اور یہ کس کمپنی کا ہے۔',
    hi: 'यह क्या है, इसका नंबर और यह किस कंपनी का है।',
  );
  static const contract = _T(
    en: 'Contract',
    ar: 'العقد',
    ur: 'معاہدہ',
    hi: 'अनुबंध',
  );
  static const contractDescription = _T(
    en: 'The job, and how many people and vehicles the LOA covers.',
    ar: 'المشروع، وعدد الأفراد والمركبات التي يشملها LOA.',
    ur: 'کام، اور LOA میں کتنے افراد اور گاڑیاں شامل ہیں۔',
    hi: 'काम, और LOA में कितने लोग और वाहन शामिल हैं।',
  );
  static const whatIsIt = _T(
    en: 'What it is',
    ar: 'النوع',
    ur: 'یہ کیا ہے',
    hi: 'यह क्या है',
  );
  static const name = _T(en: 'Name', ar: 'الاسم', ur: 'نام', hi: 'नाम');
  static const optional = _T(
    en: '{field} (optional)',
    ar: '{field} (اختياري)',
    ur: '{field} (اختیاری)',
    hi: '{field} (वैकल्पिक)',
  );
  static const errName = _T(
    en: 'Enter a name.',
    ar: 'أدخل اسمًا.',
    ur: 'نام درج کریں۔',
    hi: 'नाम दर्ज करें।',
  );
  static const errCount = _T(
    en: 'Enter a whole number.',
    ar: 'أدخل عددًا صحيحًا.',
    ur: 'پوری عدد درج کریں۔',
    hi: 'पूर्ण संख्या दर्ज करें।',
  );
  static const docLabelOptional = _T(
    en: 'Name of the document (optional)',
    ar: 'اسم المستند (اختياري)',
    ur: 'دستاویز کا نام (اختیاری)',
    hi: 'दस्तावेज़ का नाम (वैकल्पिक)',
  );

  // ─── Import and export ─────────────────────────────────────────────────────
  static const importIntro = _T(
    en: 'Choose the Staff Documents & Passes tracker, or an export from here. Nothing changes until you press Import.',
    ar: 'اختر ملف متابعة المستندات والتصاريح أو ملفًا مصدَّرًا من هنا. لن يتغير شيء حتى تضغط استيراد.',
    ur: 'اسٹاف ڈاکیومنٹس اور پاسز ٹریکر یا یہاں سے برآمد کی گئی فائل چنیں۔ درآمد دبانے تک کچھ نہیں بدلے گا۔',
    hi: 'स्टाफ़ डॉक्यूमेंट्स और पास ट्रैकर या यहाँ से निर्यात फ़ाइल चुनें। आयात दबाने तक कुछ नहीं बदलेगा।',
  );
  static const readRecords = _T(
    en: '{n} records found with {d} documents',
    ar: 'تم العثور على {n} سجلًا و{d} مستندًا',
    ur: '{n} ریکارڈ اور {d} دستاویزات ملیں',
    hi: '{n} रिकॉर्ड और {d} दस्तावेज़ मिले',
  );
  static const readKinds = _T(
    en: '{e} companies · {i} certificates · {v} vehicles · {p} policies · {c} contracts',
    ar: '{e} شركات · {i} شهادات · {v} مركبات · {p} وثائق · {c} عقود',
    ur: '{e} کمپنیاں · {i} سرٹیفکیٹ · {v} گاڑیاں · {p} پالیسیاں · {c} معاہدے',
    hi: '{e} कंपनियाँ · {i} प्रमाणपत्र · {v} वाहन · {p} पॉलिसी · {c} अनुबंध',
  );
  static const readSkipped = _T(
    en: '{n} note rows not imported',
    ar: 'لم يتم استيراد {n} من صفوف الملاحظات',
    ur: '{n} نوٹ والی قطاریں درآمد نہیں ہوئیں',
    hi: '{n} टिप्पणी पंक्तियाँ आयात नहीं हुईं',
  );
  static const noSheets = _T(
    en: 'No company sheet was found. Use the Staff Documents & Passes tracker, or an export from here.',
    ar: 'لم يتم العثور على أوراق الشركة. استخدم ملف المتابعة أو ملفًا مصدَّرًا من هنا.',
    ur: 'کمپنی کی کوئی شیٹ نہیں ملی۔ ٹریکر یا یہاں سے برآمد کی گئی فائل استعمال کریں۔',
    hi: 'कंपनी की कोई शीट नहीं मिली। ट्रैकर या यहाँ से निर्यात फ़ाइल उपयोग करें।',
  );
  static const importDone = _T(
    en: 'Imported: {n} new, {u} updated',
    ar: 'تم الاستيراد: {n} جديد، {u} محدَّث',
    ur: 'درآمد مکمل: {n} نئے، {u} تازہ',
    hi: 'आयात हुआ: {n} नए, {u} अपडेट',
  );
  static const exportDone = _T(
    en: 'Exported {n} records',
    ar: 'تم تصدير {n} سجلًا',
    ur: '{n} ریکارڈ برآمد ہوئے',
    hi: '{n} रिकॉर्ड निर्यात हुए',
  );
  static const errDenied = _T(
    en: 'You do not have access to company documents.',
    ar: 'ليس لديك صلاحية على مستندات الشركة.',
    ur: 'آپ کو کمپنی کی دستاویزات تک رسائی نہیں۔',
    hi: 'आपको कंपनी दस्तावेज़ों तक पहुँच नहीं है।',
  );
}
