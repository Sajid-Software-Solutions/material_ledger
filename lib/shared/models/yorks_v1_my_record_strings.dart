/// My Yorks from the People record, and linking accounts to people
/// (PRODUCT_DECISIONS section 54). English, Arabic, Urdu, Hindi.
///
/// Placeholders in braces are filled with [MyRecordStrings.t].
library;

import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_attendance_strings.dart';

typedef _T = TranslatableString;

abstract final class MyRecordStrings {
  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => AttendanceStrings.t(value, language, v);

  // ─── Page ──────────────────────────────────────────────────────────────────
  static const tabSettings = _T(
    en: 'Settings',
    ar: 'الإعدادات',
    ur: 'ترتیبات',
    hi: 'सेटिंग्स',
  );

  // ─── Header ────────────────────────────────────────────────────────────────
  static const documentsValid = _T(
    en: 'Documents valid',
    ar: 'المستندات سارية',
    ur: 'دستاویزات درست',
    hi: 'दस्तावेज़ मान्य',
  );
  static const documentsExpiring = _T(
    en: '{n} expiring soon',
    ar: '{n} تنتهي قريبًا',
    ur: '{n} جلد ختم ہو رہی ہیں',
    hi: '{n} जल्द समाप्त हो रहे हैं',
  );
  static const documentsExpired = _T(
    en: 'A document has expired',
    ar: 'انتهت صلاحية مستند',
    ur: 'ایک دستاویز کی میعاد ختم ہو گئی',
    hi: 'एक दस्तावेज़ समाप्त हो गया',
  );

  // ─── Me ────────────────────────────────────────────────────────────────────
  static const yourDocuments = _T(
    en: 'Your documents',
    ar: 'مستنداتك',
    ur: 'آپ کی دستاویزات',
    hi: 'आपके दस्तावेज़',
  );
  static const yourDocumentsDescription = _T(
    en: 'From your record with HR/PRO. Only the last four of each number are shown.',
    ar: 'من سجلك لدى الموارد البشرية وعلاقات الحكومة. تظهر آخر أربعة أرقام فقط من كل رقم.',
    ur: 'HR/PRO کے پاس آپ کے ریکارڈ سے۔ ہر نمبر کے صرف آخری چار ہندسے دکھائے جاتے ہیں۔',
    hi: 'HR/PRO के पास आपके रिकॉर्ड से। हर नंबर के केवल आख़िरी चार अंक दिखाए जाते हैं।',
  );
  static const endsWith = _T(
    en: 'ends {n}',
    ar: 'ينتهي بـ {n}',
    ur: 'آخر میں {n}',
    hi: 'अंत में {n}',
  );
  static const noDocuments = _T(
    en: 'No documents recorded yet',
    ar: 'لا توجد مستندات مسجلة بعد',
    ur: 'ابھی کوئی دستاویز درج نہیں',
    hi: 'अभी कोई दस्तावेज़ दर्ज नहीं',
  );
  static const onYourId = _T(
    en: 'You at Yorks',
    ar: 'أنت في يوركس',
    ur: 'یورکس میں آپ',
    hi: 'यॉर्क्स में आप',
  );
  static const onYourIdDescription = _T(
    en: 'Your position, the profession on your visa and ID, and your record with HR/PRO.',
    ar: 'منصبك، والمهنة في تأشيرتك وهويتك، وسجلك لدى الموارد البشرية وعلاقات الحكومة.',
    ur: 'آپ کا عہدہ، ویزا اور شناختی کارڈ پر پیشہ، اور HR/PRO کے پاس آپ کا ریکارڈ۔',
    hi: 'आपका पद, वीज़ा और आईडी पर पेशा, और HR/PRO के पास आपका रिकॉर्ड।',
  );
  static const professionOnId = _T(
    en: 'Profession on visa and ID',
    ar: 'المهنة في التأشيرة والهوية',
    ur: 'ویزا اور شناختی کارڈ پر پیشہ',
    hi: 'वीज़ा और आईडी पर पेशा',
  );
  static const positionInCompany = _T(
    en: 'Position in the company',
    ar: 'المنصب في الشركة',
    ur: 'کمپنی میں عہدہ',
    hi: 'कंपनी में पद',
  );
  static const recordNumber = _T(
    en: 'Record number',
    ar: 'رقم السجل',
    ur: 'ریکارڈ نمبر',
    hi: 'रिकॉर्ड नंबर',
  );
  static const company = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const category = _T(
    en: 'Category',
    ar: 'الفئة',
    ur: 'زمرہ',
    hi: 'श्रेणी',
  );
  static const joined = _T(
    en: 'Joined',
    ar: 'تاريخ الانضمام',
    ur: 'شمولیت',
    hi: 'शामिल हुए',
  );
  static const crew = _T(en: 'Crew', ar: 'الطاقم', ur: 'عملہ', hi: 'क्रू');
  static const notRecorded = _T(
    en: 'Not recorded',
    ar: 'غير مسجل',
    ur: 'درج نہیں',
    hi: 'दर्ज नहीं',
  );
  static const tellHr = _T(
    en: 'Something wrong? Tell HR/PRO',
    ar: 'هل هناك خطأ؟ أبلغ الموارد البشرية',
    ur: 'کچھ غلط ہے؟ HR/PRO کو بتائیں',
    hi: 'कुछ ग़लत है? HR/PRO को बताएँ',
  );
  static const tellHrTitle = _T(
    en: 'Tell HR/PRO',
    ar: 'أبلغ الموارد البشرية وعلاقات الحكومة',
    ur: 'HR/PRO کو بتائیں',
    hi: 'HR/PRO को बताएँ',
  );
  static const tellHrBody = _T(
    en: 'Say what is wrong, for example a date or a spelling. HR/PRO corrects your record and marks your note done.',
    ar: 'اذكر الخطأ، مثل تاريخ أو تهجئة. تصحح الموارد البشرية سجلك وتضع علامة على ملاحظتك بأنها أُنجزت.',
    ur: 'بتائیں کیا غلط ہے، مثلاً کوئی تاریخ یا ہجے۔ HR/PRO آپ کا ریکارڈ درست کر کے آپ کا نوٹ مکمل کر دے گا۔',
    hi: 'बताएँ क्या ग़लत है, जैसे कोई तारीख़ या वर्तनी। HR/PRO आपका रिकॉर्ड ठीक करके आपका नोट पूरा कर देगा।',
  );
  static const tellHrHint = _T(
    en: 'My visa expires on 12 March 2027, not 12 May.',
    ar: 'تنتهي تأشيرتي في 12 مارس 2027 وليس 12 مايو.',
    ur: 'میرا ویزا 12 مارچ 2027 کو ختم ہوتا ہے، 12 مئی کو نہیں۔',
    hi: 'मेरा वीज़ा 12 मार्च 2027 को समाप्त होता है, 12 मई को नहीं।',
  );
  static const send = _T(en: 'Send', ar: 'إرسال', ur: 'بھیجیں', hi: 'भेजें');
  static const sending = _T(
    en: 'Sending…',
    ar: 'جارٍ الإرسال…',
    ur: 'بھیجا جا رہا ہے…',
    hi: 'भेजा जा रहा है…',
  );
  static const cancel = _T(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ کریں',
    hi: 'रद्द करें',
  );
  static const sentToast = _T(
    en: 'Sent to HR/PRO',
    ar: 'أُرسلت إلى الموارد البشرية',
    ur: 'HR/PRO کو بھیج دیا گیا',
    hi: 'HR/PRO को भेजा गया',
  );
  static const noteLimit = _T(
    en: 'You have sent five notes today. Try again tomorrow.',
    ar: 'أرسلت خمس ملاحظات اليوم. حاول مرة أخرى غدًا.',
    ur: 'آپ آج پانچ نوٹ بھیج چکے ہیں۔ کل دوبارہ کوشش کریں۔',
    hi: 'आप आज पाँच नोट भेज चुके हैं। कल फिर कोशिश करें।',
  );
  static const errNoteEmpty = _T(
    en: 'Write what needs correcting',
    ar: 'اكتب ما يحتاج إلى تصحيح',
    ur: 'لکھیں کہ کیا درست کرنا ہے',
    hi: 'लिखें कि क्या ठीक करना है',
  );
  static const yourNotes = _T(
    en: 'Your notes to HR/PRO',
    ar: 'ملاحظاتك إلى الموارد البشرية',
    ur: 'HR/PRO کو آپ کے نوٹ',
    hi: 'HR/PRO को आपके नोट',
  );
  static const noteWaiting = _T(
    en: 'Sent {date} · waiting for HR/PRO',
    ar: 'أُرسلت {date} · بانتظار الموارد البشرية',
    ur: '{date} کو بھیجا · HR/PRO کا انتظار',
    hi: '{date} को भेजा · HR/PRO की प्रतीक्षा',
  );
  static const noteDoneOn = _T(
    en: 'Done {date}',
    ar: 'أُنجزت {date}',
    ur: '{date} کو مکمل',
    hi: '{date} को पूरा',
  );
  static const notLinkedTitle = _T(
    en: 'Not linked to your People record yet',
    ar: 'لم يُربط حسابك بسجلك بعد',
    ur: 'ابھی آپ کے ریکارڈ سے منسلک نہیں',
    hi: 'अभी आपके रिकॉर्ड से जुड़ा नहीं',
  );
  static const notLinkedBody = _T(
    en: 'HR/PRO links your account to your record. Until then your documents don\'t show here.',
    ar: 'تربط الموارد البشرية حسابك بسجلك. حتى ذلك الحين لن تظهر مستنداتك هنا.',
    ur: 'HR/PRO آپ کے اکاؤنٹ کو آپ کے ریکارڈ سے جوڑتا ہے۔ تب تک آپ کی دستاویزات یہاں نظر نہیں آئیں گی۔',
    hi: 'HR/PRO आपके खाते को आपके रिकॉर्ड से जोड़ता है। तब तक आपके दस्तावेज़ यहाँ नहीं दिखेंगे।',
  );
  static const recordUnavailable = _T(
    en: 'Your record could not be loaded',
    ar: 'تعذر تحميل سجلك',
    ur: 'آپ کا ریکارڈ لوڈ نہیں ہو سکا',
    hi: 'आपका रिकॉर्ड लोड नहीं हो सका',
  );
  static const retry = _T(
    en: 'Try again',
    ar: 'أعد المحاولة',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर कोशिश करें',
  );

  // ─── Settings ──────────────────────────────────────────────────────────────
  static const yourAccount = _T(
    en: 'Your account',
    ar: 'حسابك',
    ur: 'آپ کا اکاؤنٹ',
    hi: 'आपका खाता',
  );
  static const yourAccountDescription = _T(
    en: 'How you sign in to Yorks and what the app lets you do.',
    ar: 'كيف تسجل الدخول إلى يوركس وما يتيحه لك التطبيق.',
    ur: 'آپ یورکس میں کیسے سائن ان کرتے ہیں اور ایپ آپ کو کیا کرنے دیتی ہے۔',
    hi: 'आप यॉर्क्स में कैसे साइन इन करते हैं और ऐप आपको क्या करने देता है।',
  );
  static const signedInEmail = _T(
    en: 'Signed-in email',
    ar: 'البريد المستخدم لتسجيل الدخول',
    ur: 'سائن ان ای میل',
    hi: 'साइन-इन ईमेल',
  );
  static const appRole = _T(
    en: 'App role',
    ar: 'الدور في التطبيق',
    ur: 'ایپ میں کردار',
    hi: 'ऐप में भूमिका',
  );

  // ─── People: the person's account ──────────────────────────────────────────
  static const appAccount = _T(
    en: 'App account',
    ar: 'حساب التطبيق',
    ur: 'ایپ اکاؤنٹ',
    hi: 'ऐप खाता',
  );
  static const appAccountDescription = _T(
    en: 'The account this person signs in with. They see their own record in My Yorks.',
    ar: 'الحساب الذي يسجل به هذا الشخص الدخول. يرى سجله الخاص في يوركس الخاصة بي.',
    ur: 'وہ اکاؤنٹ جس سے یہ شخص سائن ان کرتا ہے۔ وہ اپنا ریکارڈ مائی یورکس میں دیکھتا ہے۔',
    hi: 'वह खाता जिससे यह व्यक्ति साइन इन करता है। वे अपना रिकॉर्ड माई यॉर्क्स में देखते हैं।',
  );
  static const notLinked = _T(
    en: 'Not linked to an app account',
    ar: 'غير مرتبط بحساب في التطبيق',
    ur: 'کسی ایپ اکاؤنٹ سے منسلک نہیں',
    hi: 'किसी ऐप खाते से जुड़ा नहीं',
  );
  static const linkAccount = _T(
    en: 'Link account',
    ar: 'ربط الحساب',
    ur: 'اکاؤنٹ منسلک کریں',
    hi: 'खाता जोड़ें',
  );
  static const changeAccount = _T(
    en: 'Change',
    ar: 'تغيير',
    ur: 'تبدیل کریں',
    hi: 'बदलें',
  );
  static const unlink = _T(
    en: 'Unlink',
    ar: 'إلغاء الربط',
    ur: 'علیحدہ کریں',
    hi: 'अलग करें',
  );
  static const unlinkTitle = _T(
    en: 'Unlink the account?',
    ar: 'إلغاء ربط الحساب؟',
    ur: 'اکاؤنٹ علیحدہ کریں؟',
    hi: 'खाता अलग करें?',
  );
  static const unlinkBody = _T(
    en: '{name} will no longer see this record in My Yorks. The record and its history stay.',
    ar: 'لن يرى {name} هذا السجل في يوركس الخاصة بي بعد الآن. يبقى السجل وتاريخه.',
    ur: '{name} یہ ریکارڈ مائی یورکس میں مزید نہیں دیکھ سکے گا۔ ریکارڈ اور اس کی تاریخ باقی رہے گی۔',
    hi: '{name} यह रिकॉर्ड माई यॉर्क्स में अब नहीं देख पाएँगे। रिकॉर्ड और उसका इतिहास बना रहेगा।',
  );
  static const linkedToast = _T(
    en: 'Account linked',
    ar: 'تم ربط الحساب',
    ur: 'اکاؤنٹ منسلک ہو گیا',
    hi: 'खाता जुड़ गया',
  );
  static const unlinkedToast = _T(
    en: 'Account unlinked',
    ar: 'تم إلغاء ربط الحساب',
    ur: 'اکاؤنٹ علیحدہ ہو گیا',
    hi: 'खाता अलग हो गया',
  );
  static const chooseAccount = _T(
    en: 'Link an account to {name}',
    ar: 'ربط حساب بـ {name}',
    ur: '{name} سے اکاؤنٹ منسلک کریں',
    hi: '{name} से खाता जोड़ें',
  );
  static const chooseAccountBody = _T(
    en: 'Accounts not yet linked to anyone. Names that match come first.',
    ar: 'حسابات غير مرتبطة بأحد بعد. الأسماء المطابقة تظهر أولًا.',
    ur: 'وہ اکاؤنٹس جو ابھی کسی سے منسلک نہیں۔ ملتے جلتے نام پہلے آتے ہیں۔',
    hi: 'ऐसे खाते जो अभी किसी से नहीं जुड़े। मिलते नाम पहले आते हैं।',
  );
  static const suggested = _T(
    en: 'Name matches',
    ar: 'الاسم مطابق',
    ur: 'نام ملتا ہے',
    hi: 'नाम मिलता है',
  );
  static const searchAccounts = _T(
    en: 'Search by name or email',
    ar: 'ابحث بالاسم أو البريد',
    ur: 'نام یا ای میل سے تلاش کریں',
    hi: 'नाम या ईमेल से खोजें',
  );
  static const noAccounts = _T(
    en: 'Every account is already linked to a person.',
    ar: 'كل الحسابات مرتبطة بأشخاص بالفعل.',
    ur: 'ہر اکاؤنٹ پہلے ہی کسی شخص سے منسلک ہے۔',
    hi: 'हर खाता पहले से किसी व्यक्ति से जुड़ा है।',
  );
  static const noMatch = _T(
    en: 'No account matches that search.',
    ar: 'لا يوجد حساب يطابق هذا البحث.',
    ur: 'اس تلاش سے کوئی اکاؤنٹ نہیں ملا۔',
    hi: 'इस खोज से कोई खाता नहीं मिला।',
  );
  static const accountTaken = _T(
    en: 'That account is already linked to someone else.',
    ar: 'هذا الحساب مرتبط بشخص آخر بالفعل.',
    ur: 'یہ اکاؤنٹ پہلے ہی کسی اور سے منسلک ہے۔',
    hi: 'यह खाता पहले से किसी और से जुड़ा है।',
  );
  static const link = _T(en: 'Link', ar: 'ربط', ur: 'منسلک کریں', hi: 'जोड़ें');
  static const hAccount = _T(
    en: '{name} changed the app account',
    ar: 'غيّر {name} حساب التطبيق',
    ur: '{name} نے ایپ اکاؤنٹ تبدیل کیا',
    hi: '{name} ने ऐप खाता बदला',
  );

  // ─── People: notes from the person ─────────────────────────────────────────
  static const notesFrom = _T(
    en: 'Notes from {name}',
    ar: 'ملاحظات من {name}',
    ur: '{name} کے نوٹ',
    hi: '{name} के नोट',
  );
  static const notesDescription = _T(
    en: 'Corrections this person asked for in My Yorks.',
    ar: 'تصحيحات طلبها هذا الشخص في يوركس الخاصة بي.',
    ur: 'وہ درستیاں جو اس شخص نے مائی یورکس میں مانگیں۔',
    hi: 'वे सुधार जो इस व्यक्ति ने माई यॉर्क्स में माँगे।',
  );
  static const markDone = _T(
    en: 'Mark done',
    ar: 'تحديد كمنجز',
    ur: 'مکمل کریں',
    hi: 'पूरा करें',
  );
  static const doneBy = _T(
    en: 'Done by {name}, {date}',
    ar: 'أنجزها {name}، {date}',
    ur: '{name} نے مکمل کیا، {date}',
    hi: '{name} ने पूरा किया, {date}',
  );
  static const openNotes = _T(
    en: '{n} open',
    ar: '{n} مفتوحة',
    ur: '{n} کھلے',
    hi: '{n} खुले',
  );
  static const noteDoneToast = _T(
    en: 'Marked done',
    ar: 'تم التحديد كمنجز',
    ur: 'مکمل کر دیا گیا',
    hi: 'पूरा किया गया',
  );

  // ─── People home: link accounts ────────────────────────────────────────────
  static const linkAccounts = _T(
    en: 'Link accounts',
    ar: 'ربط الحسابات',
    ur: 'اکاؤنٹس منسلک کریں',
    hi: 'खाते जोड़ें',
  );
  static const linkAccountsTitle = _T(
    en: 'Link accounts to people',
    ar: 'ربط الحسابات بالأشخاص',
    ur: 'اکاؤنٹس کو افراد سے منسلک کریں',
    hi: 'खातों को लोगों से जोड़ें',
  );
  static const linkAccountsDescription = _T(
    en: 'Once linked, each person sees their own record in My Yorks and is reminded when their documents expire.',
    ar: 'بعد الربط، يرى كل شخص سجله في يوركس الخاصة بي ويُذكَّر عند انتهاء مستنداته.',
    ur: 'منسلک ہونے کے بعد ہر شخص اپنا ریکارڈ مائی یورکس میں دیکھتا ہے اور دستاویزات ختم ہونے پر یاد دہانی پاتا ہے۔',
    hi: 'जुड़ने के बाद हर व्यक्ति अपना रिकॉर्ड माई यॉर्क्स में देखता है और दस्तावेज़ समाप्त होने पर याद दिलाया जाता है।',
  );
  static const linkSummary = _T(
    en: '{linked} linked · {waiting} accounts not linked · {matches} with a name match',
    ar: '{linked} مرتبطة · {waiting} غير مرتبطة · {matches} بأسماء مطابقة',
    ur: '{linked} منسلک · {waiting} غیر منسلک · {matches} کا نام ملتا ہے',
    hi: '{linked} जुड़े · {waiting} नहीं जुड़े · {matches} के नाम मिलते हैं',
  );
  static const linkTo = _T(
    en: 'Link to {name}',
    ar: 'ربط بـ {name}',
    ur: '{name} سے منسلک کریں',
    hi: '{name} से जोड़ें',
  );
  static const noSuggestion = _T(
    en: 'No name match. Open the person\'s record and choose Link account.',
    ar: 'لا يوجد اسم مطابق. افتح سجل الشخص واختر ربط الحساب.',
    ur: 'کوئی نام نہیں ملا۔ شخص کا ریکارڈ کھولیں اور اکاؤنٹ منسلک کریں منتخب کریں۔',
    hi: 'कोई नाम नहीं मिला। व्यक्ति का रिकॉर्ड खोलें और खाता जोड़ें चुनें।',
  );
  static const close = _T(
    en: 'Close',
    ar: 'إغلاق',
    ur: 'بند کریں',
    hi: 'बंद करें',
  );

  // ─── User Management: the account's People record (section 56) ─────────────
  static const peopleRecord = _T(
    en: 'People record',
    ar: 'السجل في الأفراد',
    ur: 'افراد میں ریکارڈ',
    hi: 'लोग में रिकॉर्ड',
  );
  static const peopleRecordDescription = _T(
    en: 'The person this account belongs to. They see this record in My Yorks.',
    ar: 'الشخص الذي يخصه هذا الحساب. يرى هذا السجل في يوركس الخاصة بي.',
    ur: 'وہ شخص جس کا یہ اکاؤنٹ ہے۔ وہ یہ ریکارڈ مائی یورکس میں دیکھتا ہے۔',
    hi: 'वह व्यक्ति जिसका यह खाता है। वे यह रिकॉर्ड माई यॉर्क्स में देखते हैं।',
  );
  static const noPeopleRecord = _T(
    en: 'Not linked to a person yet',
    ar: 'غير مرتبط بشخص بعد',
    ur: 'ابھی کسی شخص سے منسلک نہیں',
    hi: 'अभी किसी व्यक्ति से जुड़ा नहीं',
  );
  static const noPeopleRecordHint = _T(
    en: 'Link it so My Yorks shows their documents and details.',
    ar: 'اربطه ليعرض يوركس الخاصة بي مستنداته وبياناته.',
    ur: 'منسلک کریں تاکہ مائی یورکس ان کی دستاویزات اور تفصیلات دکھائے۔',
    hi: 'जोड़ें ताकि माई यॉर्क्स उनके दस्तावेज़ और विवरण दिखाए।',
  );
  static const hrLinksPeople = _T(
    en: 'HR/PRO or Admin links accounts to people.',
    ar: 'تربط الموارد البشرية وعلاقات الحكومة أو الإدارة الحسابات بالأشخاص.',
    ur: 'HR/PRO یا ایڈمن اکاؤنٹس کو افراد سے منسلک کرتے ہیں۔',
    hi: 'HR/PRO या एडमिन खातों को लोगों से जोड़ते हैं।',
  );
  static const openRecord = _T(
    en: 'Open record',
    ar: 'فتح السجل',
    ur: 'ریکارڈ کھولیں',
    hi: 'रिकॉर्ड खोलें',
  );
  static const choosePerson = _T(
    en: 'Link {name} to a person',
    ar: 'ربط {name} بشخص',
    ur: '{name} کو کسی شخص سے منسلک کریں',
    hi: '{name} को किसी व्यक्ति से जोड़ें',
  );
  static const choosePersonBody = _T(
    en: 'Choose the person this account belongs to. Names that match come first.',
    ar: 'اختر الشخص الذي يخصه هذا الحساب. الأسماء المطابقة تظهر أولًا.',
    ur: 'وہ شخص چنیں جس کا یہ اکاؤنٹ ہے۔ ملتے جلتے نام پہلے آتے ہیں۔',
    hi: 'वह व्यक्ति चुनें जिसका यह खाता है। मिलते नाम पहले आते हैं।',
  );
  static const searchPeople = _T(
    en: 'Search name or record number',
    ar: 'ابحث بالاسم أو رقم السجل',
    ur: 'نام یا ریکارڈ نمبر تلاش کریں',
    hi: 'नाम या रिकॉर्ड नंबर खोजें',
  );
  static const noPersonMatch = _T(
    en: 'No one matches that search.',
    ar: 'لا يوجد أحد يطابق هذا البحث.',
    ur: 'اس تلاش سے کوئی نہیں ملا۔',
    hi: 'इस खोज से कोई नहीं मिला।',
  );
  static const linkedToOther = _T(
    en: 'Linked to {name}',
    ar: 'مرتبط بـ {name}',
    ur: '{name} سے منسلک',
    hi: '{name} से जुड़ा',
  );
  static const unlinkPersonBody = _T(
    en: '{name} will no longer see their record in My Yorks. The record and its history stay.',
    ar: 'لن يرى {name} سجله في يوركس الخاصة بي بعد الآن. يبقى السجل وتاريخه.',
    ur: '{name} اب مائی یورکس میں اپنا ریکارڈ نہیں دیکھے گا۔ ریکارڈ اور اس کی تاریخ باقی رہیں گے۔',
    hi: '{name} अब माई यॉर्क्स में अपना रिकॉर्ड नहीं देखेंगे। रिकॉर्ड और उसका इतिहास बना रहेगा।',
  );
}
