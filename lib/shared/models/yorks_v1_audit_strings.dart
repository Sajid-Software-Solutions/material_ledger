import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_audit_workspace.dart';

abstract final class YorksV1AuditStrings {
  static const workspace = TranslatableString(
    en: 'Audit Workspace',
    ar: 'مساحة عمل التدقيق',
    ur: 'آڈٹ ورک اسپیس',
    hi: 'ऑडिट कार्यक्षेत्र',
  );
  static const title = TranslatableString(
    en: 'System audit & integrity',
    ar: 'تدقيق النظام وسلامته',
    ur: 'سسٹم آڈٹ اور سالمیت',
    hi: 'सिस्टम ऑडिट और अखंडता',
  );
  static const subtitle = TranslatableString(
    en: 'Trusted, server-recorded activity across Yorks operations.',
    ar: 'نشاط موثوق ومسجل على الخادم عبر عمليات يوركس.',
    ur: 'یورکس آپریشنز میں قابل اعتماد سرور ریکارڈ شدہ سرگرمی۔',
    hi: 'यॉर्क्स संचालन में विश्वसनीय सर्वर-रिकॉर्ड की गई गतिविधि।',
  );
  static const searchHint = TranslatableString(
    en: 'Search actor, reference, project or action…',
    ar: 'ابحث عن المنفذ أو المرجع أو المشروع أو الإجراء…',
    ur: 'صارف، حوالہ، پروجیکٹ یا کارروائی تلاش کریں…',
    hi: 'कर्ता, संदर्भ, प्रोजेक्ट या कार्रवाई खोजें…',
  );
  static const totalActivities = TranslatableString(
    en: 'Total activities',
    ar: 'إجمالي الأنشطة',
    ur: 'کل سرگرمیاں',
    hi: 'कुल गतिविधियाँ',
  );
  static const criticalActivities = TranslatableString(
    en: 'Critical activities',
    ar: 'الأنشطة الحرجة',
    ur: 'اہم سرگرمیاں',
    hi: 'महत्वपूर्ण गतिविधियाँ',
  );
  static const activeUsers = TranslatableString(
    en: 'Active actors',
    ar: 'المنفذون النشطون',
    ur: 'فعال صارفین',
    hi: 'सक्रिय कर्ता',
  );
  static const entitiesMonitored = TranslatableString(
    en: 'Records with activity',
    ar: 'سجلات ذات نشاط',
    ur: 'سرگرمی والے ریکارڈ',
    hi: 'गतिविधि वाले रिकॉर्ड',
  );
  static const auditAlerts = TranslatableString(
    en: 'Flagged events',
    ar: 'أحداث معلّمة',
    ur: 'نشان زد واقعات',
    hi: 'चिह्नित इवेंट',
  );
  static const dataIntegrity = TranslatableString(
    en: 'Attribution coverage',
    ar: 'تغطية الإسناد',
    ur: 'نسبت کی کوریج',
    hi: 'एट्रिब्यूशन कवरेज',
  );
  static const allTime = TranslatableString(
    en: 'All recorded time',
    ar: 'كل الوقت المسجل',
    ur: 'تمام ریکارڈ شدہ وقت',
    hi: 'सभी रिकॉर्ड किए गए समय',
  );
  static const lastThirtyDays = TranslatableString(
    en: 'Last 30 days',
    ar: 'آخر 30 يومًا',
    ur: 'گزشتہ 30 دن',
    hi: 'पिछले 30 दिन',
  );
  static const lastSevenDays = TranslatableString(
    en: 'Last 7 days',
    ar: 'آخر 7 أيام',
    ur: 'گزشتہ 7 دن',
    hi: 'पिछले 7 दिन',
  );
  static const trustedCoverage = TranslatableString(
    en: 'Immutable actor + exact-role coverage',
    ar: 'تغطية المنفذ والدور الدقيق غير القابلة للتغيير',
    ur: 'ناقابل تبدیلی صارف اور درست کردار کی کوریج',
    hi: 'अपरिवर्तनीय कर्ता और सटीक भूमिका कवरेज',
  );
  static const recentActivity = TranslatableString(
    en: 'Recent activity feed',
    ar: 'سجل النشاط الأخير',
    ur: 'حالیہ سرگرمی فیڈ',
    hi: 'हाल की गतिविधि फ़ीड',
  );
  static const recentActivityHint = TranslatableString(
    en: 'Latest trusted events across all monitored modules',
    ar: 'أحدث الأحداث الموثوقة عبر جميع الوحدات المراقبة',
    ur: 'تمام نگرانی شدہ ماڈیولز کے تازہ ترین قابل اعتماد واقعات',
    hi: 'सभी निगरानी मॉड्यूलों की नवीनतम विश्वसनीय घटनाएँ',
  );
  static const timeColumn = TranslatableString(
    en: 'TIME',
    ar: 'الوقت',
    ur: 'وقت',
    hi: 'समय',
  );
  static const userColumn = TranslatableString(
    en: 'USER',
    ar: 'المستخدم',
    ur: 'صارف',
    hi: 'उपयोगकर्ता',
  );
  static const actionColumn = TranslatableString(
    en: 'ACTION',
    ar: 'الإجراء',
    ur: 'کارروائی',
    hi: 'कार्रवाई',
  );
  static const moduleColumn = TranslatableString(
    en: 'MODULE',
    ar: 'الوحدة',
    ur: 'ماڈیول',
    hi: 'मॉड्यूल',
  );
  static const entityColumn = TranslatableString(
    en: 'ENTITY',
    ar: 'الكيان',
    ur: 'ادارہ',
    hi: 'इकाई',
  );
  static const referenceColumn = TranslatableString(
    en: 'REFERENCE',
    ar: 'المرجع',
    ur: 'حوالہ',
    hi: 'संदर्भ',
  );
  static const detailsColumn = TranslatableString(
    en: 'DETAILS',
    ar: 'التفاصيل',
    ur: 'تفصیلات',
    hi: 'विवरण',
  );
  static const total = TranslatableString(
    en: 'Total',
    ar: 'الإجمالي',
    ur: 'کل',
    hi: 'कुल',
  );
  static const topEntities = TranslatableString(
    en: 'Top entities by activity',
    ar: 'أعلى الكيانات حسب النشاط',
    ur: 'سرگرمی کے لحاظ سے سرفہرست ادارے',
    hi: 'गतिविधि के अनुसार शीर्ष इकाइयाँ',
  );
  static const quickFilters = TranslatableString(
    en: 'Quick filters',
    ar: 'مرشحات سريعة',
    ur: 'فوری فلٹرز',
    hi: 'त्वरित फ़िल्टर',
  );
  static const alerts = TranslatableString(
    en: 'Alerts & exceptions',
    ar: 'التنبيهات والاستثناءات',
    ur: 'الرٹس اور استثنات',
    hi: 'अलर्ट और अपवाद',
  );
  static const activityOverview = TranslatableString(
    en: 'Activity overview',
    ar: 'نظرة عامة على النشاط',
    ur: 'سرگرمی کا جائزہ',
    hi: 'गतिविधि अवलोकन',
  );
  static const activityOverviewHint = TranslatableString(
    en: 'Trends, modules, activity leaders and flagged events for the selected scope',
    ar: 'الاتجاهات والوحدات وأبرز الأنشطة والأحداث المعلّمة للنطاق المحدد',
    ur: 'منتخب دائرے کے رجحانات، ماڈیولز، نمایاں سرگرمیاں اور نشان زد واقعات',
    hi: 'चुने गए दायरे के रुझान, मॉड्यूल, प्रमुख गतिविधियाँ और चिह्नित इवेंट',
  );
  static const activityTrend = TranslatableString(
    en: 'Activity trend',
    ar: 'اتجاه النشاط',
    ur: 'سرگرمی کا رجحان',
    hi: 'गतिविधि रुझान',
  );
  static const auditHealth = TranslatableString(
    en: 'Audit health score',
    ar: 'مؤشر صحة التدقيق',
    ur: 'آڈٹ ہیلتھ اسکور',
    hi: 'ऑडिट स्वास्थ्य स्कोर',
  );
  static const trusted = TranslatableString(
    en: 'Trusted',
    ar: 'موثوق',
    ur: 'قابل اعتماد',
    hi: 'विश्वसनीय',
  );
  static const historicalGap = TranslatableString(
    en: 'Historical attribution gaps',
    ar: 'فجوات الإسناد التاريخية',
    ur: 'تاریخی نسبت کے خلا',
    hi: 'ऐतिहासिक एट्रिब्यूशन अंतराल',
  );
  static const noEvents = TranslatableString(
    en: 'No trusted audit events match these filters',
    ar: 'لا توجد أحداث تدقيق موثوقة تطابق هذه المرشحات',
    ur: 'کوئی قابل اعتماد آڈٹ واقعہ ان فلٹرز سے مماثل نہیں',
    hi: 'इन फ़िल्टरों से कोई विश्वसनीय ऑडिट घटना मेल नहीं खाती',
  );
  static const noEventsHint = TranslatableString(
    en: 'Clear a filter or wait for a server-confirmed action.',
    ar: 'امسح مرشحًا أو انتظر إجراءً مؤكداً من الخادم.',
    ur: 'فلٹر صاف کریں یا سرور سے تصدیق شدہ کارروائی کا انتظار کریں۔',
    hi: 'फ़िल्टर साफ़ करें या सर्वर-पुष्ट कार्रवाई की प्रतीक्षा करें।',
  );
  static const unavailable = TranslatableString(
    en: 'Trusted audit records are unavailable',
    ar: 'سجلات التدقيق الموثوقة غير متاحة',
    ur: 'قابل اعتماد آڈٹ ریکارڈ دستیاب نہیں',
    hi: 'विश्वसनीय ऑडिट रिकॉर्ड उपलब्ध नहीं हैं',
  );
  static const unavailableHint = TranslatableString(
    en: 'Nothing was changed. Check access and connection, then retry.',
    ar: 'لم يتغير شيء. تحقق من الوصول والاتصال ثم أعد المحاولة.',
    ur: 'کچھ تبدیل نہیں ہوا۔ رسائی اور کنکشن چیک کریں، پھر کوشش کریں۔',
    hi: 'कुछ नहीं बदला। पहुँच और कनेक्शन जाँचें, फिर पुनः प्रयास करें।',
  );
  static const refresh = TranslatableString(
    en: 'Refresh trusted records',
    ar: 'تحديث السجلات الموثوقة',
    ur: 'قابل اعتماد ریکارڈ تازہ کریں',
    hi: 'विश्वसनीय रिकॉर्ड ताज़ा करें',
  );
  static const retry = TranslatableString(
    en: 'Retry',
    ar: 'إعادة المحاولة',
    ur: 'دوبارہ کوشش',
    hi: 'पुनः प्रयास',
  );
  static const allModules = TranslatableString(
    en: 'All modules',
    ar: 'جميع الوحدات',
    ur: 'تمام ماڈیولز',
    hi: 'सभी मॉड्यूल',
  );
  static const verifiedActor = TranslatableString(
    en: 'Verified server attribution',
    ar: 'إسناد خادم موثق',
    ur: 'تصدیق شدہ سرور نسبت',
    hi: 'सत्यापित सर्वर एट्रिब्यूशन',
  );
  static const legacyActor = TranslatableString(
    en: 'Historical role snapshot unavailable',
    ar: 'لقطة الدور التاريخية غير متاحة',
    ur: 'تاریخی کردار سنیپ شاٹ دستیاب نہیں',
    hi: 'ऐतिहासिक भूमिका स्नैपशॉट उपलब्ध नहीं',
  );

  static TranslatableString module(YorksV1AuditModule module) =>
      switch (module) {
        YorksV1AuditModule.accounts => const TranslatableString(
          en: 'Accounts',
          ar: 'الحسابات',
          ur: 'اکاؤنٹس',
          hi: 'लेखा',
        ),
        YorksV1AuditModule.workforce => const TranslatableString(
          en: 'Workforce',
          ar: 'القوى العاملة',
          ur: 'افرادی قوت',
          hi: 'कार्यबल',
        ),
        YorksV1AuditModule.configuration => const TranslatableString(
          en: 'Configuration',
          ar: 'الإعدادات',
          ur: 'ترتیبات',
          hi: 'कॉन्फ़िगरेशन',
        ),
        YorksV1AuditModule.projects => const TranslatableString(
          en: 'Projects & BOQ',
          ar: 'المشاريع وجداول الكميات',
          ur: 'پروجیکٹس اور BOQ',
          hi: 'प्रोजेक्ट और BOQ',
        ),
        YorksV1AuditModule.materialRequests => const TranslatableString(
          en: 'Material requests',
          ar: 'طلبات المواد',
          ur: 'میٹیریل ریکویسٹس',
          hi: 'सामग्री अनुरोध',
        ),
        YorksV1AuditModule.logistics => const TranslatableString(
          en: 'Dispatch & receipt',
          ar: 'الإرسال والاستلام',
          ur: 'ڈسپیچ اور رسید',
          hi: 'डिस्पैच और प्राप्ति',
        ),
        YorksV1AuditModule.inventory => const TranslatableString(
          en: 'Inventory',
          ar: 'المخزون',
          ur: 'انوینٹری',
          hi: 'इन्वेंटरी',
        ),
        YorksV1AuditModule.rentals => const TranslatableString(
          en: 'Rental properties',
          ar: 'العقارات المؤجرة',
          ur: 'رینٹل پراپرٹیز',
          hi: 'किराये की संपत्तियाँ',
        ),
        YorksV1AuditModule.users => const TranslatableString(
          en: 'User management',
          ar: 'إدارة المستخدمين',
          ur: 'صارف مینجمنٹ',
          hi: 'उपयोगकर्ता प्रबंधन',
        ),
        YorksV1AuditModule.documents => const TranslatableString(
          en: 'Documents',
          ar: 'المستندات',
          ur: 'دستاویزات',
          hi: 'दस्तावेज़',
        ),
        YorksV1AuditModule.system => const TranslatableString(
          en: 'System',
          ar: 'النظام',
          ur: 'سسٹم',
          hi: 'सिस्टम',
        ),
      };

  static TranslatableString quickFilter(YorksV1AuditQuickFilter filter) =>
      switch (filter) {
        YorksV1AuditQuickFilter.critical => const TranslatableString(
          en: 'Critical activity',
          ar: 'نشاط حرج',
          ur: 'اہم سرگرمی',
          hi: 'महत्वपूर्ण गतिविधि',
        ),
        YorksV1AuditQuickFilter.exceptions => const TranslatableString(
          en: 'Exceptions',
          ar: 'الاستثناءات',
          ur: 'استثنات',
          hi: 'अपवाद',
        ),
        YorksV1AuditQuickFilter.dataChanges => const TranslatableString(
          en: 'Data changes',
          ar: 'تغييرات البيانات',
          ur: 'ڈیٹا تبدیلیاں',
          hi: 'डेटा परिवर्तन',
        ),
        YorksV1AuditQuickFilter.approvals => const TranslatableString(
          en: 'Approvals',
          ar: 'الموافقات',
          ur: 'منظوریاں',
          hi: 'अनुमोदन',
        ),
        YorksV1AuditQuickFilter.access => const TranslatableString(
          en: 'Access changes',
          ar: 'تغييرات الوصول',
          ur: 'رسائی کی تبدیلیاں',
          hi: 'पहुँच परिवर्तन',
        ),
      };

  static String eventLabel(String eventType, AppLanguage language) {
    final known = <String, TranslatableString>{
      'company_request_draft_created': const TranslatableString(
        en: 'Company draft saved',
        ar: 'تم حفظ مسودة الشركة',
        ur: 'کمپنی مسودہ محفوظ',
        hi: 'कंपनी ड्राफ्ट सहेजा गया',
      ),
      'company_request_submitted': const TranslatableString(
        en: 'Company request submitted',
        ar: 'تم إرسال طلب الشركة',
        ur: 'کمپنی درخواست جمع ہوئی',
        hi: 'कंपनी अनुरोध जमा हुआ',
      ),
      'company_request_approved': const TranslatableString(
        en: 'Company request approved',
        ar: 'تمت الموافقة على طلب الشركة',
        ur: 'کمپنی درخواست منظور',
        hi: 'कंपनी अनुरोध स्वीकृत',
      ),
      'company_request_returned': const TranslatableString(
        en: 'Company request returned for changes',
        ar: 'أعيد طلب الشركة للتعديل',
        ur: 'کمپنی درخواست ترمیم کے لیے واپس',
        hi: 'कंपनी अनुरोध संशोधन हेतु वापस',
      ),
      'company_request_rejected': const TranslatableString(
        en: 'Company request rejected',
        ar: 'رُفض طلب الشركة',
        ur: 'کمپنی درخواست مسترد',
        hi: 'कंपनी अनुरोध अस्वीकृत',
      ),
      'company_request_resubmitted': const TranslatableString(
        en: 'Company request resubmitted',
        ar: 'أعيد إرسال طلب الشركة',
        ur: 'کمپنی درخواست دوبارہ جمع',
        hi: 'कंपनी अनुरोध फिर जमा',
      ),
      'company_supply_plan_saved': const TranslatableString(
        en: 'Company arrangement saved',
        ar: 'تم حفظ ترتيب مواد الشركة',
        ur: 'کمپنی انتظام محفوظ',
        hi: 'कंपनी व्यवस्था सहेजी गई',
      ),
      'company_material_dispatched': const TranslatableString(
        en: 'Company materials dispatched',
        ar: 'تم إرسال مواد الشركة',
        ur: 'کمپنی مواد روانہ',
        hi: 'कंपनी सामग्री भेजी गई',
      ),
      'company_receipt_confirmed': const TranslatableString(
        en: 'Company receipt reviewed',
        ar: 'تمت مراجعة استلام الشركة',
        ur: 'کمپنی وصولی کا جائزہ مکمل',
        hi: 'कंपनी प्राप्ति की समीक्षा हुई',
      ),
      'company_beneficiary_handover_confirmed': const TranslatableString(
        en: 'Company beneficiary handover confirmed',
        ar: 'تم تأكيد التسليم للمستفيد',
        ur: 'کمپنی مستفید کو حوالگی کی تصدیق',
        hi: 'कंपनी लाभार्थी हस्तांतरण पुष्ट',
      ),
      'company_return_submitted': const TranslatableString(
        en: 'Company return submitted',
        ar: 'تم إرسال مرتجع الشركة',
        ur: 'کمپنی واپسی جمع ہوئی',
        hi: 'कंपनी वापसी जमा हुई',
      ),
      'company_return_confirmed': const TranslatableString(
        en: 'Company return confirmed',
        ar: 'تم تأكيد مرتجع الشركة',
        ur: 'کمپنی واپسی کی تصدیق',
        hi: 'कंपनी वापसी पुष्ट',
      ),
      'company_return_rejected': const TranslatableString(
        en: 'Company return rejected',
        ar: 'رُفض مرتجع الشركة',
        ur: 'کمپنی واپسی مسترد',
        hi: 'कंपनी वापसी अस्वीकृत',
      ),
      'company_request_cancelled': const TranslatableString(
        en: 'Company request cancelled',
        ar: 'أُلغي طلب الشركة',
        ur: 'کمپنی درخواست منسوخ',
        hi: 'कंपनी अनुरोध रद्द',
      ),
      'company_request_closed': const TranslatableString(
        en: 'Company request closed',
        ar: 'أغلق طلب الشركة',
        ur: 'کمپنی درخواست بند',
        hi: 'कंपनी अनुरोध बंद',
      ),
      'company_request_remainder_withdrawn': const TranslatableString(
        en: 'Company remaining need withdrawn',
        ar: 'سُحبت الحاجة المتبقية للشركة',
        ur: 'کمپنی باقی ضرورت واپس',
        hi: 'कंपनी शेष आवश्यकता वापस ली गई',
      ),
      'project_created': const TranslatableString(
        en: 'Project created',
        ar: 'تم إنشاء المشروع',
        ur: 'پروجیکٹ بنایا گیا',
        hi: 'प्रोजेक्ट बनाया गया',
      ),
      'project_updated': const TranslatableString(
        en: 'Project updated',
        ar: 'تم تحديث المشروع',
        ur: 'پروجیکٹ اپ ڈیٹ ہوا',
        hi: 'प्रोजेक्ट अपडेट हुआ',
      ),
      'project_archived': const TranslatableString(
        en: 'Project archived',
        ar: 'تمت أرشفة المشروع',
        ur: 'پروجیکٹ آرکائیو ہوا',
        hi: 'प्रोजेक्ट संग्रहित हुआ',
      ),
      'material_request_submitted': const TranslatableString(
        en: 'Material request submitted',
        ar: 'تم إرسال طلب المواد',
        ur: 'میٹیریل ریکویسٹ جمع ہوئی',
        hi: 'सामग्री अनुरोध जमा हुआ',
      ),
      'material_request_cancelled': const TranslatableString(
        en: 'Material request cancelled',
        ar: 'تم إلغاء طلب المواد',
        ur: 'میٹیریل ریکویسٹ منسوخ ہوئی',
        hi: 'सामग्री अनुरोध रद्द हुआ',
      ),
      'material_request_closed': const TranslatableString(
        en: 'Material request closed',
        ar: 'تم إغلاق طلب المواد',
        ur: 'میٹیریل ریکویسٹ بند ہوئی',
        hi: 'सामग्री अनुरोध बंद हुआ',
      ),
      'arrangement_started': const TranslatableString(
        en: 'Arrangement started',
        ar: 'بدأ الترتيب',
        ur: 'انتظام شروع ہوا',
        hi: 'व्यवस्था शुरू हुई',
      ),
      'arrangement_saved': const TranslatableString(
        en: 'Arrangement saved',
        ar: 'تم حفظ الترتيب',
        ur: 'انتظام محفوظ ہوا',
        hi: 'व्यवस्था सहेजी गई',
      ),
      'arrangement_approved': const TranslatableString(
        en: 'Arrangement approved',
        ar: 'تمت الموافقة على الترتيب',
        ur: 'انتظام منظور ہوا',
        hi: 'व्यवस्था स्वीकृत हुई',
      ),
      'arrangement_returned': const TranslatableString(
        en: 'Arrangement returned',
        ar: 'تمت إعادة الترتيب',
        ur: 'انتظام واپس ہوا',
        hi: 'व्यवस्था वापस की गई',
      ),
      'materials_dispatched': const TranslatableString(
        en: 'Materials dispatched',
        ar: 'تم إرسال المواد',
        ur: 'مواد روانہ ہوئے',
        hi: 'सामग्री भेजी गई',
      ),
      'receipt_review_confirmed': const TranslatableString(
        en: 'Receipt review confirmed',
        ar: 'تم تأكيد مراجعة الاستلام',
        ur: 'رسید جائزہ تصدیق ہوا',
        hi: 'प्राप्ति समीक्षा पुष्ट हुई',
      ),
      'delivery_order_generated': const TranslatableString(
        en: 'Delivery Order generated',
        ar: 'تم إنشاء أمر التسليم',
        ur: 'ڈیلیوری آرڈر بنا',
        hi: 'डिलीवरी ऑर्डर बना',
      ),
      'delivery_order_superseded': const TranslatableString(
        en: 'Delivery Order revision created',
        ar: 'تم إنشاء مراجعة لأمر التسليم',
        ur: 'ڈیلیوری آرڈر ریویژن بنا',
        hi: 'डिलीवरी ऑर्डर संशोधन बना',
      ),
      'inventory_item_created': const TranslatableString(
        en: 'Inventory item created',
        ar: 'تم إنشاء عنصر مخزون',
        ur: 'انوینٹری آئٹم بنا',
        hi: 'इन्वेंटरी आइटम बना',
      ),
      'inventory_adjusted': const TranslatableString(
        en: 'Inventory adjusted',
        ar: 'تم تعديل المخزون',
        ur: 'انوینٹری ایڈجسٹ ہوئی',
        hi: 'इन्वेंटरी समायोजित हुई',
      ),
      'rental_property_created': const TranslatableString(
        en: 'Rental property created',
        ar: 'تم إنشاء عقار مؤجر',
        ur: 'رینٹل پراپرٹی بنی',
        hi: 'किराये की संपत्ति बनी',
      ),
      'rental_property_updated': const TranslatableString(
        en: 'Rental property updated',
        ar: 'تم تحديث العقار المؤجر',
        ur: 'رینٹل پراپرٹی اپ ڈیٹ ہوئی',
        hi: 'किराये की संपत्ति अपडेट हुई',
      ),
      'auth_user_role_changed': const TranslatableString(
        en: 'User role changed',
        ar: 'تم تغيير دور المستخدم',
        ur: 'صارف کردار تبدیل ہوا',
        hi: 'उपयोगकर्ता भूमिका बदली',
      ),
      'user_commercial_capability_changed': const TranslatableString(
        en: 'Commercial access changed',
        ar: 'تم تغيير الوصول التجاري',
        ur: 'کمرشل رسائی تبدیل ہوئی',
        hi: 'व्यावसायिक पहुँच बदली',
      ),
      'document_linked': const TranslatableString(
        en: 'Document linked',
        ar: 'تم ربط المستند',
        ur: 'دستاویز منسلک ہوئی',
        hi: 'दस्तावेज़ जोड़ा गया',
      ),
    };
    final copy = known[eventType];
    if (copy != null) return copy.active(language);
    return eventType
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String roleLabel(String exactRole, AppLanguage language) {
    final copy = switch (exactRole) {
      'project_engineer' => const TranslatableString(
        en: 'Project Engineer',
        ar: 'مهندس المشروع',
        ur: 'پروجیکٹ انجینئر',
        hi: 'प्रोजेक्ट इंजीनियर',
      ),
      'site_engineer' => const TranslatableString(
        en: 'Site Engineer',
        ar: 'مهندس الموقع',
        ur: 'سائٹ انجینئر',
        hi: 'साइट इंजीनियर',
      ),
      'senior_mechanical_engineer' => const TranslatableString(
        en: 'Senior Mechanical Engineer',
        ar: 'مهندس ميكانيكي أول',
        ur: 'سینئر مکینیکل انجینئر',
        hi: 'वरिष्ठ मैकेनिकल इंजीनियर',
      ),
      'project_manager' => const TranslatableString(
        en: 'Project Manager',
        ar: 'مدير المشروع',
        ur: 'پروجیکٹ مینیجر',
        hi: 'प्रोजेक्ट प्रबंधक',
      ),
      'workshop_in_charge' => AppStrings.workshopInChargeRole,
      'document_controller' => AppStrings.documentControllerRole,
      'accountant' => AppStrings.accountantRole,
      'pr' => AppStrings.prRole,
      'procurement' => const TranslatableString(
        en: 'Procurement',
        ar: 'المشتريات',
        ur: 'پروکیورمنٹ',
        hi: 'खरीद',
      ),
      'admin' => const TranslatableString(
        en: 'Admin',
        ar: 'مسؤول',
        ur: 'ایڈمن',
        hi: 'एडमिन',
      ),
      _ => const TranslatableString(
        en: 'Historical role',
        ar: 'دور تاريخي',
        ur: 'تاریخی کردار',
        hi: 'ऐतिहासिक भूमिका',
      ),
    };
    return copy.active(language);
  }

  static String entityLabel(String entityType, AppLanguage language) {
    if (entityType == 'company_material_request') {
      return const TranslatableString(
        en: 'Company material request',
        ar: 'طلب مواد الشركة',
        ur: 'کمپنی مٹیریل درخواست',
        hi: 'कंपनी सामग्री अनुरोध',
      ).active(language);
    }
    final normalized = entityType.replaceAll('_', ' ');
    if (language != AppLanguage.english) return normalized;
    if (normalized.isEmpty) return '';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}
