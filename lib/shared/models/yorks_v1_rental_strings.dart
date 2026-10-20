import 'package:flutter/widgets.dart';

/// Copy for the simplified rental workspace controls, keyed independently of
/// stored property types, contract states and controlled workbook headings.
abstract final class RentalWorkspaceStrings {
  static String missingField(BuildContext context, String key) {
    final localizedKey = 'missing_$key';
    return _copy.containsKey(localizedKey)
        ? text(context, localizedKey)
        : key.replaceAll('_', ' ');
  }

  static String text(BuildContext context, String key) {
    final values = _copy[key]!;
    return values[Localizations.localeOf(context).languageCode] ??
        values['en']!;
  }

  static const _copy = {
    'chequeActions': {
      'en': 'Cheque actions',
      'ar': 'إجراءات الشيك',
      'ur': 'چیک کے اقدامات',
      'hi': 'चेक की कार्रवाइयाँ',
    },
    'chequeAction_received': {
      'en': 'Mark received',
      'ar': 'تسجيل الاستلام',
      'ur': 'موصول درج کریں',
      'hi': 'प्राप्त दर्ज करें',
    },
    'chequeAction_deposited': {
      'en': 'Mark deposited',
      'ar': 'تسجيل الإيداع',
      'ur': 'جمع شدہ درج کریں',
      'hi': 'जमा दर्ज करें',
    },
    'chequeAction_cleared': {
      'en': 'Mark cleared',
      'ar': 'تسجيل التحصيل',
      'ur': 'کلیئر شدہ درج کریں',
      'hi': 'समाशोधित दर्ज करें',
    },
    'chequeAction_returned': {
      'en': 'Mark returned',
      'ar': 'تسجيل الارتجاع',
      'ur': 'واپس شدہ درج کریں',
      'hi': 'वापस दर्ज करें',
    },
    'chequeAction_cancelled': {
      'en': 'Mark cancelled',
      'ar': 'تسجيل الإلغاء',
      'ur': 'منسوخ درج کریں',
      'hi': 'रद्द दर्ज करें',
    },
    'chequeStatus_scheduled': {
      'en': 'Scheduled',
      'ar': 'مجدول',
      'ur': 'طے شدہ',
      'hi': 'निर्धारित',
    },
    'chequeStatus_received': {
      'en': 'Received',
      'ar': 'مستلم',
      'ur': 'موصول',
      'hi': 'प्राप्त',
    },
    'chequeStatus_deposited': {
      'en': 'Deposited',
      'ar': 'مودع',
      'ur': 'جمع شدہ',
      'hi': 'जमा',
    },
    'chequeStatus_cleared': {
      'en': 'Cleared',
      'ar': 'محصل',
      'ur': 'کلیئر شدہ',
      'hi': 'समाशोधित',
    },
    'chequeStatus_returned': {
      'en': 'Returned',
      'ar': 'مرتجع',
      'ur': 'واپس شدہ',
      'hi': 'वापस',
    },
    'chequeStatus_cancelled': {
      'en': 'Cancelled',
      'ar': 'ملغى',
      'ur': 'منسوخ',
      'hi': 'रद्द',
    },
    'chequeReason': {
      'en': 'Change reason',
      'ar': 'سبب التغيير',
      'ur': 'تبدیلی کی وجہ',
      'hi': 'बदलाव का कारण',
    },
    'chequeReasonHelp': {
      'en':
          'Returning or cancelling a cheque requires a reason in its audit history.',
      'ar': 'يتطلب ارتجاع الشيك أو إلغاؤه تسجيل السبب في سجل التدقيق.',
      'ur': 'چیک واپس یا منسوخ کرنے کی وجہ آڈٹ ریکارڈ میں درج کرنا ضروری ہے۔',
      'hi':
          'चेक लौटाने या रद्द करने का कारण उसके ऑडिट इतिहास में दर्ज करना आवश्यक है।',
    },
    'chequeReasonRequired': {
      'en': 'A reason is required.',
      'ar': 'السبب مطلوب.',
      'ur': 'وجہ درج کرنا ضروری ہے۔',
      'hi': 'कारण आवश्यक है।',
    },
    'cancelAction': {
      'en': 'Cancel',
      'ar': 'إلغاء',
      'ur': 'منسوخ کریں',
      'hi': 'रद्द करें',
    },
    'chequeUpdated': {
      'en': 'Cheque status updated.',
      'ar': 'تم تحديث حالة الشيك.',
      'ur': 'چیک کی حالت تبدیل ہو گئی۔',
      'hi': 'चेक की स्थिति अपडेट हुई।',
    },
    'chequeNotUpdated': {
      'en':
          'Cheque status was not updated. Check the details and reload the property if it changed.',
      'ar':
          'لم يتم تحديث حالة الشيك. تحقق من التفاصيل وأعد تحميل العقار إذا تغير.',
      'ur':
          'چیک کی حالت تبدیل نہیں ہوئی۔ تفصیلات دیکھیں اور تبدیلی کی صورت میں جائیداد دوبارہ لوڈ کریں۔',
      'hi':
          'चेक की स्थिति अपडेट नहीं हुई। विवरण जाँचें और बदलाव होने पर संपत्ति फिर लोड करें।',
    },
    'chequeUnconfirmed': {
      'en':
          'The status could not be confirmed. Your reason is kept here. Retry the same change safely.',
      'ar':
          'تعذر تأكيد الحالة. السبب محفوظ هنا. أعد محاولة التغيير نفسه بأمان.',
      'ur':
          'حالت کی تصدیق نہیں ہوئی۔ وجہ یہاں محفوظ ہے۔ اسی تبدیلی کی محفوظ دوبارہ کوشش کریں۔',
      'hi':
          'स्थिति की पुष्टि नहीं हुई। कारण यहाँ सुरक्षित है। उसी बदलाव को सुरक्षित दोहराएँ।',
    },
    'retryChequeStatus': {
      'en': 'Confirm status change',
      'ar': 'تأكيد تغيير الحالة',
      'ur': 'حالت کی تبدیلی کی تصدیق کریں',
      'hi': 'स्थिति बदलाव की पुष्टि करें',
    },
    'recordPayment': {
      'en': 'Record payment',
      'ar': 'تسجيل الدفعة',
      'ur': 'ادائیگی درج کریں',
      'hi': 'भुगतान दर्ज करें',
    },
    'confirmPayment': {
      'en': 'Confirm payment',
      'ar': 'تأكيد الدفعة',
      'ur': 'ادائیگی کی تصدیق کریں',
      'hi': 'भुगतान की पुष्टि करें',
    },
    'paymentRecorded': {
      'en': 'Rent payment recorded.',
      'ar': 'تم تسجيل دفعة الإيجار.',
      'ur': 'کرایہ کی ادائیگی درج ہو گئی۔',
      'hi': 'किराया भुगतान दर्ज हुआ।',
    },
    'paymentUnconfirmed': {
      'en':
          'The payment could not be confirmed. Your entries are kept here. Confirm payment safely retries the same request. Do not record it again as a new payment.',
      'ar':
          'تعذر تأكيد الدفعة. بياناتك محفوظة هنا. تأكيد الدفعة يعيد الطلب نفسه بأمان. لا تسجلها كدفعة جديدة.',
      'ur':
          'ادائیگی کی تصدیق نہیں ہو سکی۔ معلومات محفوظ ہیں۔ تصدیق سے اسی درخواست کی محفوظ دوبارہ کوشش ہو گی۔ نئی ادائیگی دوبارہ درج نہ کریں۔',
      'hi':
          'भुगतान की पुष्टि नहीं हुई। विवरण सुरक्षित है। पुष्टि उसी अनुरोध को सुरक्षित दोहराती है। इसे नया भुगतान बनाकर दोबारा दर्ज न करें।',
    },
    'paymentRejected': {
      'en':
          'The payment was rejected. Check the details and reload the property if it changed.',
      'ar': 'تم رفض الدفعة. تحقق من البيانات وأعد تحميل العقار إذا تغير.',
      'ur':
          'ادائیگی مسترد ہوئی۔ تفصیلات دیکھیں اور تبدیلی کی صورت میں جائیداد دوبارہ لوڈ کریں۔',
      'hi':
          'भुगतान अस्वीकार हुआ। विवरण जाँचें और बदलाव होने पर संपत्ति फिर लोड करें।',
    },
    'unconfirmedShort': {
      'en': 'Not confirmed',
      'ar': 'غير مؤكد',
      'ur': 'غیر مصدقہ',
      'hi': 'पुष्टि बाकी',
    },
    'occupied': {
      'en': 'Occupied',
      'ar': 'مشغول',
      'ur': 'آباد',
      'hi': 'अधिभोगित',
    },
    'vacant': {'en': 'Vacant', 'ar': 'شاغر', 'ur': 'خالی', 'hi': 'खाली'},
    'annualOption': {
      'en': 'Annual',
      'ar': 'سنوي',
      'ur': 'سالانہ',
      'hi': 'वार्षिक',
    },
    'monthlyOption': {
      'en': 'Monthly',
      'ar': 'شهري',
      'ur': 'ماہانہ',
      'hi': 'मासिक',
    },
    'chequeReview': {
      'en': 'Cheque requires review',
      'ar': 'الشيك يحتاج إلى مراجعة',
      'ur': 'چیک کا جائزہ لیں',
      'hi': 'चेक की समीक्षा करें',
    },
    'reviewDetails': {
      'en': 'Review missing details',
      'ar': 'مراجعة البيانات الناقصة',
      'ur': 'نامکمل تفصیلات دیکھیں',
      'hi': 'अधूरे विवरण देखें',
    },
    'perYear': {'en': 'year', 'ar': 'سنة', 'ur': 'سال', 'hi': 'वर्ष'},
    'perMonth': {'en': 'month', 'ar': 'شهر', 'ur': 'ماہ', 'hi': 'महीना'},
    'invalidNumber': {
      'en': 'Enter a valid non-negative number.',
      'ar': 'أدخل رقماً صحيحاً غير سالب.',
      'ur': 'درست غیر منفی عدد درج کریں۔',
      'hi': 'मान्य गैर-ऋणात्मक संख्या दर्ज करें।',
    },
    'annualRentRoll': {
      'en': 'Annual rent roll',
      'ar': 'إجمالي الإيجار السنوي',
      'ur': 'سالانہ کرایہ',
      'hi': 'वार्षिक किराया',
    },
    'annualRent': {
      'en': 'Annual Rent (AED)',
      'ar': 'الإيجار السنوي (درهم)',
      'ur': 'سالانہ کرایہ (درہم)',
      'hi': 'वार्षिक किराया (AED)',
    },
    'monthlyRent': {
      'en': 'Monthly Rent (AED)',
      'ar': 'الإيجار الشهري (درهم)',
      'ur': 'ماہانہ کرایہ (درہم)',
      'hi': 'मासिक किराया (AED)',
    },
    'completionTitle': {
      'en': 'Complete property details',
      'ar': 'استكمال بيانات العقارات',
      'ur': 'جائیداد کی تفصیلات مکمل کریں',
      'hi': 'संपत्ति का विवरण पूरा करें',
    },
    'completionHelp': {
      'en':
          'These records are saved. Add the missing details whenever available. Open a property and choose Edit property.',
      'ar':
          'تم حفظ هذه السجلات. أضف البيانات الناقصة عند توفرها. افتح العقار واختر تعديل العقار.',
      'ur':
          'یہ ریکارڈ محفوظ ہیں۔ معلومات دستیاب ہونے پر شامل کریں۔ جائیداد کھول کر ترمیم کریں۔',
      'hi':
          'ये रिकॉर्ड सहेजे गए हैं। जानकारी उपलब्ध होने पर जोड़ें। संपत्ति खोलकर संपादित करें।',
    },
    'billingStart': {
      'en': 'First rent date to track',
      'ar': 'أول تاريخ إيجار للمتابعة',
      'ur': 'کرایہ ٹریک کرنے کی پہلی تاریخ',
      'hi': 'किराया ट्रैक करने की पहली तारीख',
    },
    'billingStartHelp': {
      'en':
          'Leave blank while the opening balance is unconfirmed. Selecting a date creates unpaid rent periods from that date. Historical receipts must be recorded separately.',
      'ar':
          'اتركه فارغاً حتى تأكيد الرصيد الافتتاحي. تحديد تاريخ ينشئ فترات إيجار غير مدفوعة من ذلك التاريخ. سجّل الإيصالات السابقة بشكل منفصل.',
      'ur':
          'ابتدائی بیلنس غیر مصدقہ ہو تو خالی چھوڑیں۔ تاریخ منتخب کرنے سے اس دن سے غیر ادا شدہ کرایہ بنے گا۔ پچھلی رسیدیں الگ درج کریں۔',
      'hi':
          'शुरुआती शेष की पुष्टि तक खाली छोड़ें। तारीख चुनने से उस दिन से अवैतनिक किराया बनेगा। पुरानी रसीदें अलग दर्ज करें।',
    },
    'balancePending': {
      'en': 'Opening balance unconfirmed',
      'ar': 'الرصيد الافتتاحي غير مؤكد',
      'ur': 'ابتدائی بیلنس غیر مصدقہ',
      'hi': 'शुरुआती शेष की पुष्टि बाकी',
    },
    'importedSource': {
      'en': 'Imported source details',
      'ar': 'بيانات المصدر المستوردة',
      'ur': 'درآمد شدہ اصل تفصیلات',
      'hi': 'आयातित स्रोत विवरण',
    },
    'unknown': {
      'en': 'Unknown',
      'ar': 'غير محدد',
      'ur': 'نامعلوم',
      'hi': 'अज्ञात',
    },
    'missing_location': {
      'en': 'Site location',
      'ar': 'موقع العقار',
      'ur': 'مقام',
      'hi': 'स्थान',
    },
    'missing_contact_number': {
      'en': 'Contact number',
      'ar': 'رقم التواصل',
      'ur': 'رابطہ نمبر',
      'hi': 'संपर्क नंबर',
    },
    'missing_contract_number': {
      'en': 'Contract number',
      'ar': 'رقم العقد',
      'ur': 'معاہدہ نمبر',
      'hi': 'अनुबंध नंबर',
    },
    'missing_tenant_name': {
      'en': 'Tenant / company name',
      'ar': 'اسم المستأجر / الشركة',
      'ur': 'کرایہ دار / کمپنی کا نام',
      'hi': 'किरायेदार / कंपनी का नाम',
    },
    'missing_lease_start': {
      'en': 'Lease start',
      'ar': 'بداية العقد',
      'ur': 'معاہدہ شروع',
      'hi': 'पट्टा शुरू',
    },
    'missing_lease_end': {
      'en': 'Lease end',
      'ar': 'نهاية العقد',
      'ur': 'معاہدہ ختم',
      'hi': 'पट्टा समाप्त',
    },
    'missing_rent_amount': {
      'en': 'Rent amount',
      'ar': 'قيمة الإيجار',
      'ur': 'کرایہ کی رقم',
      'hi': 'किराया राशि',
    },
    'missing_billing_start': {
      'en': 'Opening balance and first rent date',
      'ar': 'الرصيد الافتتاحي وأول تاريخ إيجار',
      'ur': 'ابتدائی بیلنس اور کرایہ کی پہلی تاریخ',
      'hi': 'शुरुआती शेष और किराए की पहली तारीख',
    },
    'missing_property_type': {
      'en': 'Property type',
      'ar': 'نوع العقار',
      'ur': 'جائیداد کی قسم',
      'hi': 'संपत्ति का प्रकार',
    },
    'missing_occupancy': {
      'en': 'Occupancy',
      'ar': 'الإشغال',
      'ur': 'رہائش کی حالت',
      'hi': 'अधिभोग',
    },
    'missing_source_unit_number': {
      'en': 'Unit number',
      'ar': 'رقم الوحدة',
      'ur': 'یونٹ نمبر',
      'hi': 'यूनिट नंबर',
    },
    'missing_source_property_type': {
      'en': 'Original property type',
      'ar': 'نوع العقار الأصلي',
      'ur': 'اصل جائیداد کی قسم',
      'hi': 'मूल संपत्ति प्रकार',
    },
    'workbookIssues': {
      'en': 'Workbook issues',
      'ar': 'مشكلات ملف الاستيراد',
      'ur': 'ورک بک کے مسائل',
      'hi': 'वर्कबुक की समस्याएँ',
    },
    'importFormatHelp': {
      'en':
          'Use the rental import format. Keep each worksheet name and its header row.',
      'ar':
          'استخدم قالب استيراد الإيجارات مع الحفاظ على أسماء أوراق العمل وصف العناوين.',
      'ur':
          'کرایہ درآمد کا نمونہ استعمال کریں۔ ہر شیٹ کا نام اور عنوانات کی قطار برقرار رکھیں۔',
      'hi':
          'किराया आयात टेम्पलेट का उपयोग करें। हर शीट का नाम और शीर्षक पंक्ति बनाए रखें।',
    },
    'schedule': {
      'en': 'Rent Schedule',
      'ar': 'جدول الإيجار',
      'ur': 'کرایہ شیڈول',
      'hi': 'किराया अनुसूची',
    },
    'documents': {
      'en': 'Documents',
      'ar': 'المستندات',
      'ur': 'دستاویزات',
      'hi': 'दस्तावेज़',
    },
    'activity': {
      'en': 'Activity',
      'ar': 'النشاط',
      'ur': 'سرگرمی',
      'hi': 'गतिविधि',
    },
    'edit': {
      'en': 'Edit property',
      'ar': 'تعديل العقار',
      'ur': 'جائیداد میں ترمیم',
      'hi': 'संपत्ति संपादित करें',
    },
    'archive': {
      'en': 'Archive',
      'ar': 'أرشفة',
      'ur': 'محفوظات',
      'hi': 'संग्रह करें',
    },

    'saved': {
      'en': 'Rental property saved.',
      'ar': 'تم حفظ العقار.',
      'ur': 'جائیداد محفوظ ہو گئی۔',
      'hi': 'संपत्ति सहेज दी गई।',
    },
    'saving': {
      'en': 'Saving…',
      'ar': 'جارٍ الحفظ…',
      'ur': 'محفوظ ہو رہا ہے…',
      'hi': 'सहेजा जा रहा है…',
    },
    'retrySave': {
      'en': 'Confirm save',
      'ar': 'تأكيد الحفظ',
      'ur': 'محفوظ کرنے کی تصدیق',
      'hi': 'सहेजने की पुष्टि करें',
    },
    'create': {
      'en': 'Create property',
      'ar': 'إنشاء عقار',
      'ur': 'جائیداد بنائیں',
      'hi': 'संपत्ति बनाएँ',
    },
    'save': {
      'en': 'Save property',
      'ar': 'حفظ العقار',
      'ur': 'جائیداد محفوظ کریں',
      'hi': 'संपत्ति सहेजें',
    },
    'unconfirmed': {
      'en':
          'The save could not be confirmed. Your entries are kept here. Confirm save retries the same request safely before further changes.',
      'ar':
          'تعذر تأكيد الحفظ. بياناتك محفوظة هنا. أعد تأكيد الطلب نفسه بأمان قبل إجراء تغييرات أخرى.',
      'ur':
          'محفوظ ہونے کی تصدیق نہیں ہوئی۔ آپ کی معلومات یہاں موجود ہیں۔ مزید تبدیلی سے پہلے اسی درخواست کی دوبارہ تصدیق کریں۔',
      'hi':
          'सहेजने की पुष्टि नहीं हो सकी। आपकी जानकारी यहाँ रखी गई है। बदलाव से पहले उसी अनुरोध की सुरक्षित पुष्टि करें।',
    },
    'conflict': {
      'en':
          'This property changed since you opened it. Your entries are kept here. Close and reload the property before applying changes.',
      'ar':
          'تغير العقار منذ فتحه. بياناتك موجودة هنا. أغلق وأعد تحميل العقار قبل تطبيق التغييرات.',
      'ur':
          'کھولنے کے بعد جائیداد تبدیل ہوئی ہے۔ معلومات یہاں موجود ہیں۔ تبدیلی سے پہلے بند کر کے دوبارہ کھولیں۔',
      'hi':
          'खोलने के बाद संपत्ति बदल गई है। आपकी जानकारी यहाँ है। बदलाव से पहले बंद करके फिर लोड करें।',
    },
    'saveFailed': {
      'en':
          'The property was not saved. Your entries are kept here. Check the details and your connection, then try again.',
      'ar':
          'لم يتم حفظ العقار. بياناتك موجودة هنا. تحقق من التفاصيل والاتصال ثم حاول مجدداً.',
      'ur':
          'جائیداد محفوظ نہیں ہوئی۔ معلومات یہاں موجود ہیں۔ تفصیلات اور رابطہ دیکھ کر دوبارہ کوشش کریں۔',
      'hi':
          'संपत्ति सहेजी नहीं गई। जानकारी यहाँ है। विवरण और कनेक्शन जाँचकर फिर कोशिश करें।',
    },

    'title': {
      'en': 'Rental Properties',
      'ar': 'العقارات المؤجرة',
      'ur': 'کرائے کی جائیدادیں',
      'hi': 'किराये की संपत्तियाँ',
    },
    'refresh': {
      'en': 'Refresh rental register',
      'ar': 'تحديث سجل الإيجارات',
      'ur': 'کرایہ رجسٹر تازہ کریں',
      'hi': 'किराया रजिस्टर रीफ़्रेश करें',
    },
    'import': {
      'en': 'Import Excel',
      'ar': 'استيراد Excel',
      'ur': 'Excel درآمد کریں',
      'hi': 'Excel आयात करें',
    },
    'template': {
      'en': 'Download import format',
      'ar': 'تنزيل قالب الاستيراد',
      'ur': 'درآمد کا نمونہ ڈاؤن لوڈ کریں',
      'hi': 'आयात टेम्पलेट डाउनलोड करें',
    },
    'export': {
      'en': 'Export rental registers',
      'ar': 'تصدير سجلات الإيجار',
      'ur': 'کرایہ رجسٹر برآمد کریں',
      'hi': 'किराया रजिस्टर निर्यात करें',
    },
    'add': {
      'en': 'Add property',
      'ar': 'إضافة عقار',
      'ur': 'جائیداد شامل کریں',
      'hi': 'संपत्ति जोड़ें',
    },
    'overview': {
      'en': 'Overview',
      'ar': 'نظرة عامة',
      'ur': 'جائزہ',
      'hi': 'अवलोकन',
    },
    'properties': {
      'en': 'Property register',
      'ar': 'سجل العقارات',
      'ur': 'جائیداد رجسٹر',
      'hi': 'संपत्ति रजिस्टर',
    },
    'payments': {
      'en': 'Payments',
      'ar': 'الدفعات',
      'ur': 'ادائیگیاں',
      'hi': 'भुगतान',
    },
    'cheques': {
      'en': 'CDC / PDC',
      'ar': 'شيكات حالية / مؤجلة',
      'ur': 'CDC / PDC',
      'hi': 'CDC / PDC',
    },
    'expiry': {
      'en': 'Lease expiry',
      'ar': 'انتهاء الإيجار',
      'ur': 'لیز کی میعاد',
      'hi': 'लीज़ की समाप्ति',
    },
    'emptyTitle': {
      'en': 'Add your first rental property',
      'ar': 'أضف أول عقار مؤجر',
      'ur': 'اپنی پہلی کرائے کی جائیداد شامل کریں',
      'hi': 'अपनी पहली किराये की संपत्ति जोड़ें',
    },
    'emptyBody': {
      'en':
          'Add a property or import your Excel workbook. Then manage its lease, rent and payments here.',
      'ar': 'أضف عقاراً أو استورد ملف Excel، ثم تابع عقد الإيجار والدفعات هنا.',
      'ur':
          'جائیداد شامل کریں یا Excel فائل درآمد کریں۔ پھر یہاں لیز، کرایہ اور ادائیگیوں کا انتظام کریں۔',
      'hi':
          'संपत्ति जोड़ें या Excel फ़ाइल आयात करें। फिर यहाँ लीज़, किराया और भुगतान प्रबंधित करें।',
    },
  };
}
