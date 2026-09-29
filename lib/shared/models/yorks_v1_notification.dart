import '../../app/router.dart' show RoutePaths;
import 'app_language.dart';
import 'app_notification.dart';
import 'app_strings.dart';

const yorksV1ChatTransportEventCodes = <String>{
  'team_chat_message',
  'team_chat_mention',
};

bool yorksV1IsChatTransportEvent({
  required String eventCode,
  String entityType = '',
}) =>
    eventCode != 'material_request_mentioned' &&
    (yorksV1ChatTransportEventCodes.contains(eventCode) ||
        entityType == 'chat_message' ||
        entityType == 'chat_conversation');

class YorksV1NotificationRecord {
  const YorksV1NotificationRecord({
    required this.id,
    required this.eventCode,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.requestId,
    this.projectId,
    this.chatConversationId,
    this.seenAt,
  });

  final String id;
  final String eventCode;
  final String entityType;
  final String entityId;
  final String? requestId;
  final String? projectId;
  final String? chatConversationId;
  final DateTime createdAt;
  final DateTime? seenAt;

  /// Chat uses its member read cursor as the authoritative unread state. These
  /// rows remain backend-only inputs to the durable FCM outbox and must never
  /// appear in, or increment, the workflow notification centre.
  bool get isChatTransport =>
      yorksV1IsChatTransportEvent(eventCode: eventCode, entityType: entityType);

  YorksV1NotificationRecord acknowledgedAt(DateTime value) =>
      YorksV1NotificationRecord(
        id: id,
        eventCode: eventCode,
        entityType: entityType,
        entityId: entityId,
        requestId: requestId,
        projectId: projectId,
        chatConversationId: chatConversationId,
        createdAt: createdAt,
        seenAt: value,
      );

  factory YorksV1NotificationRecord.fromRpcJson(Map<String, dynamic> json) {
    return YorksV1NotificationRecord(
      id: json['notification_id'] as String,
      eventCode: json['event_code'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      requestId: json['request_id'] as String?,
      projectId: json['project_id'] as String?,
      chatConversationId: json['chat_conversation_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      seenAt: json['seen_at'] == null
          ? null
          : DateTime.parse(json['seen_at'] as String).toLocal(),
    );
  }

  AppNotification toAppNotification(AppLanguage language) {
    final copy = YorksV1NotificationCopy.forEvent(eventCode);
    final resolvedRequestId = requestId?.trim() ?? '';
    final resolvedProjectId = projectId?.trim() ?? '';
    final resolvedChatConversationId = chatConversationId?.trim() ?? '';
    final isMaterialReturn = entityType == 'material_return';
    final isCompanyMaterialRequest = entityType == 'company_material_request';
    final isMaterialRequestCommentMention =
        eventCode == 'material_request_mentioned' &&
        entityType == 'chat_message' &&
        resolvedRequestId.isNotEmpty;
    final resolvedRoute = isMaterialRequestCommentMention
        ? RoutePaths.yorksV1MaterialRequestPath(
            resolvedRequestId,
            commentId: entityId,
          )
        : resolvedChatConversationId.isNotEmpty
        ? RoutePaths.yorksV1TeamChatPath(resolvedChatConversationId)
        : isMaterialReturn
        ? RoutePaths.yorksV1MaterialReturnPath(entityId)
        : isCompanyMaterialRequest
        ? RoutePaths.yorksV1CompanyMaterialRequestPath(entityId)
        : resolvedRequestId.isNotEmpty
        ? RoutePaths.yorksV1MaterialRequestPath(resolvedRequestId)
        : resolvedProjectId.isNotEmpty &&
              (entityType == 'project' || entityType == 'project_member')
        ? RoutePaths.yorksV1ProjectPath(resolvedProjectId)
        : '';
    return AppNotification(
      id: id,
      type: copy.type,
      title: copy.title(language),
      titleSecondary: '',
      body: resolvedRoute.isEmpty
          ? AppStrings.notificationDetailsUnavailable.active(language)
          : copy.body(language),
      timestamp: createdAt,
      isRead: seenAt != null,
      refId: isMaterialReturn
          ? entityId
          : resolvedRequestId.isNotEmpty
          ? resolvedRequestId
          : entityId,
      route: resolvedRoute,
      origin: NotificationOrigin.yorksV1,
    );
  }
}

class YorksV1NotificationCopy {
  const YorksV1NotificationCopy({
    required this.type,
    required this.englishTitle,
    required this.englishBody,
    required this.arabicTitle,
    required this.arabicBody,
    required this.urduTitle,
    required this.urduBody,
    required this.hindiTitle,
    required this.hindiBody,
  });

  final NotificationType type;
  final String englishTitle;
  final String englishBody;
  final String arabicTitle;
  final String arabicBody;
  final String urduTitle;
  final String urduBody;
  final String hindiTitle;
  final String hindiBody;

  String title(AppLanguage language) => switch (language) {
    AppLanguage.english => englishTitle,
    AppLanguage.arabic => arabicTitle,
    AppLanguage.urdu => urduTitle,
    AppLanguage.hindi => hindiTitle,
  };

  String body(AppLanguage language) => switch (language) {
    AppLanguage.english => englishBody,
    AppLanguage.arabic => arabicBody,
    AppLanguage.urdu => urduBody,
    AppLanguage.hindi => hindiBody,
  };

  static YorksV1NotificationCopy forEvent(String eventCode) =>
      _eventCopy[eventCode] ?? _workflowUpdate;
}

const _workflowUpdate = YorksV1NotificationCopy(
  type: NotificationType.info,
  englishTitle: 'Yorks workflow update',
  englishBody: 'A record assigned to you has changed.',
  arabicTitle: 'تحديث سير عمل يوركس',
  arabicBody: 'تم تغيير سجل مسند إليك.',
  urduTitle: 'یورکس ورک فلو اپ ڈیٹ',
  urduBody: 'آپ کو تفویض کردہ ریکارڈ تبدیل ہوا ہے۔',
  hindiTitle: 'यॉर्क्स कार्यप्रवाह अपडेट',
  hindiBody: 'आपको सौंपा गया रिकॉर्ड बदल गया है।',
);

const _requestApprovalRequired = YorksV1NotificationCopy(
  type: NotificationType.request,
  englishTitle: 'Material request approval required',
  englishBody: 'A material request is ready for Engineering approval.',
  arabicTitle: 'مطلوب اعتماد طلب المواد',
  arabicBody: 'طلب مواد جاهز لاعتماد الهندسة.',
  urduTitle: 'مٹیریل ریکویسٹ کی منظوری درکار ہے',
  urduBody: 'مٹیریل ریکویسٹ انجینئرنگ منظوری کے لیے تیار ہے۔',
  hindiTitle: 'सामग्री अनुरोध की स्वीकृति आवश्यक',
  hindiBody: 'सामग्री अनुरोध इंजीनियरिंग स्वीकृति के लिए तैयार है।',
);

const _requestApprovedForArrangement = YorksV1NotificationCopy(
  type: NotificationType.request,
  englishTitle: 'Material request approved',
  englishBody: 'Engineering approved the request for Procurement arrangement.',
  arabicTitle: 'تم اعتماد طلب المواد',
  arabicBody: 'اعتمدت الهندسة الطلب لترتيب المشتريات.',
  urduTitle: 'مٹیریل ریکویسٹ منظور',
  urduBody: 'انجینئرنگ نے پروکیورمنٹ انتظام کے لیے ریکویسٹ منظور کر لی ہے۔',
  hindiTitle: 'सामग्री अनुरोध स्वीकृत',
  hindiBody: 'इंजीनियरिंग ने खरीद व्यवस्था के लिए अनुरोध स्वीकृत कर दिया है।',
);

const _requestChangesRequired = YorksV1NotificationCopy(
  type: NotificationType.request,
  englishTitle: 'Material request changes required',
  englishBody: 'Engineering returned the request with a reason.',
  arabicTitle: 'مطلوب تعديل طلب المواد',
  arabicBody: 'أعادت الهندسة الطلب مع السبب.',
  urduTitle: 'مٹیریل ریکویسٹ میں تبدیلی درکار ہے',
  urduBody: 'انجینئرنگ نے ریکویسٹ وجہ کے ساتھ واپس کر دی ہے۔',
  hindiTitle: 'सामग्री अनुरोध में बदलाव आवश्यक',
  hindiBody: 'इंजीनियरिंग ने कारण सहित अनुरोध वापस कर दिया है।',
);

const _requestMention = YorksV1NotificationCopy(
  type: NotificationType.info,
  englishTitle: 'You were mentioned',
  englishBody: 'A teammate mentioned you in a material request comment.',
  arabicTitle: 'تمت الإشارة إليك',
  arabicBody: 'أشار إليك زميل في تعليق على طلب مواد.',
  urduTitle: 'آپ کا ذکر کیا گیا',
  urduBody: 'ایک ساتھی نے مٹیریل ریکویسٹ کے تبصرے میں آپ کا ذکر کیا ہے۔',
  hindiTitle: 'आपका उल्लेख किया गया',
  hindiBody: 'एक साथी ने सामग्री अनुरोध टिप्पणी में आपका उल्लेख किया है।',
);

const _requestWorkAssigned = YorksV1NotificationCopy(
  type: NotificationType.request,
  englishTitle: 'Material request assigned to you',
  englishBody: 'A teammate assigned you responsibility for a material request.',
  arabicTitle: 'تم إسناد طلب مواد إليك',
  arabicBody: 'أسند إليك أحد الزملاء مسؤولية متابعة طلب مواد.',
  urduTitle: 'مٹیریل ریکویسٹ آپ کو تفویض کی گئی',
  urduBody: 'ایک ساتھی نے مٹیریل ریکویسٹ کی ذمہ داری آپ کو تفویض کی ہے۔',
  hindiTitle: 'सामग्री अनुरोध आपको सौंपा गया',
  hindiBody: 'एक सहकर्मी ने सामग्री अनुरोध की जिम्मेदारी आपको सौंपी है।',
);

const _eventCopy = <String, YorksV1NotificationCopy>{
  'company_material_request_approval_requested': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request approval required',
    englishBody: 'A company material request is waiting for your decision.',
    arabicTitle: 'مطلوب اعتماد طلب مواد الشركة',
    arabicBody: 'طلب مواد للشركة بانتظار قرارك.',
    urduTitle: 'کمپنی مٹیریل درخواست کی منظوری درکار ہے',
    urduBody: 'کمپنی مٹیریل درخواست آپ کے فیصلے کی منتظر ہے۔',
    hindiTitle: 'कंपनी सामग्री अनुरोध की स्वीकृति आवश्यक',
    hindiBody: 'एक कंपनी सामग्री अनुरोध आपके निर्णय की प्रतीक्षा में है।',
  ),
  'company_material_request_approved': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request approved',
    englishBody: 'Your company material request was approved.',
    arabicTitle: 'تم اعتماد طلب مواد الشركة',
    arabicBody: 'تم اعتماد طلب مواد الشركة الخاص بك.',
    urduTitle: 'کمپنی مٹیریل درخواست منظور',
    urduBody: 'آپ کی کمپنی مٹیریل درخواست منظور ہو گئی۔',
    hindiTitle: 'कंपनी सामग्री अनुरोध स्वीकृत',
    hindiBody: 'आपका कंपनी सामग्री अनुरोध स्वीकृत हो गया।',
  ),
  'company_material_request_returned': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request changes required',
    englishBody: 'Your company material request was returned with a reason.',
    arabicTitle: 'مطلوب تعديل طلب مواد الشركة',
    arabicBody: 'تمت إعادة طلب مواد الشركة الخاص بك مع السبب.',
    urduTitle: 'کمپنی مٹیریل درخواست میں تبدیلی درکار ہے',
    urduBody: 'آپ کی کمپنی مٹیریل درخواست وجہ کے ساتھ واپس کر دی گئی۔',
    hindiTitle: 'कंपनी सामग्री अनुरोध में बदलाव आवश्यक',
    hindiBody: 'आपका कंपनी सामग्री अनुरोध कारण सहित लौटाया गया।',
  ),
  'company_material_request_rejected': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request rejected',
    englishBody: 'Your company material request was rejected with a reason.',
    arabicTitle: 'تم رفض طلب مواد الشركة',
    arabicBody: 'تم رفض طلب مواد الشركة الخاص بك مع السبب.',
    urduTitle: 'کمپنی مٹیریل درخواست مسترد',
    urduBody: 'آپ کی کمپنی مٹیریل درخواست وجہ کے ساتھ مسترد کر دی گئی۔',
    hindiTitle: 'कंपनी सामग्री अनुरोध अस्वीकृत',
    hindiBody: 'आपका कंपनी सामग्री अनुरोध कारण सहित अस्वीकृत किया गया।',
  ),
  'company_material_request_supply_planned': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request supply planned',
    englishBody:
        'Procurement updated the supply plan for your company request.',
    arabicTitle: 'تم تخطيط توريد طلب الشركة',
    arabicBody: 'حدّثت المشتريات خطة التوريد لطلب الشركة الخاص بك.',
    urduTitle: 'کمپنی درخواست کی سپلائی پلان ہو گئی',
    urduBody: 'پروکیورمنٹ نے آپ کی کمپنی درخواست کا سپلائی پلان اپ ڈیٹ کیا۔',
    hindiTitle: 'कंपनी अनुरोध की आपूर्ति योजना बनी',
    hindiBody: 'खरीद टीम ने आपके कंपनी अनुरोध की आपूर्ति योजना अपडेट की।',
  ),
  'company_material_request_dispatched': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company materials dispatched',
    englishBody: 'Company materials are waiting for your receipt review.',
    arabicTitle: 'تم إرسال مواد الشركة',
    arabicBody: 'مواد الشركة بانتظار مراجعة الاستلام منك.',
    urduTitle: 'کمپنی مٹیریل روانہ ہو گیا',
    urduBody: 'کمپنی مٹیریل آپ کی وصولی جانچ کا منتظر ہے۔',
    hindiTitle: 'कंपनी सामग्री भेजी गई',
    hindiBody: 'कंपनी सामग्री आपकी प्राप्ति समीक्षा की प्रतीक्षा में है।',
  ),
  'company_material_request_received': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company materials received',
    englishBody: 'Good received quantities are ready for beneficiary handover.',
    arabicTitle: 'تم استلام مواد الشركة',
    arabicBody: 'الكميات المستلمة بحالة جيدة جاهزة للتسليم للمستفيد.',
    urduTitle: 'کمپنی مٹیریل موصول ہو گیا',
    urduBody: 'اچھی حالت میں موصول مقدار مستفید کو حوالگی کے لیے تیار ہے۔',
    hindiTitle: 'कंपनी सामग्री प्राप्त हुई',
    hindiBody: 'अच्छी प्राप्त मात्रा लाभार्थी को सौंपने के लिए तैयार है।',
  ),
  'company_material_request_handed_over': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Beneficiary handover confirmed',
    englishBody: 'The company material beneficiary handover was recorded.',
    arabicTitle: 'تم تأكيد التسليم للمستفيد',
    arabicBody: 'تم تسجيل تسليم مواد الشركة للمستفيد.',
    urduTitle: 'مستفید کو حوالگی کی تصدیق',
    urduBody: 'کمپنی مٹیریل کی مستفید کو حوالگی ریکارڈ ہو گئی۔',
    hindiTitle: 'लाभार्थी को सौंपना दर्ज हुआ',
    hindiBody: 'कंपनी सामग्री लाभार्थी को सौंपने का रिकॉर्ड दर्ज हुआ।',
  ),
  'company_material_request_return_confirmed': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company material return confirmed',
    englishBody:
        'Procurement confirmed physical receipt of the returned material.',
    arabicTitle: 'تم تأكيد مرتجع مواد الشركة',
    arabicBody: 'أكدت المشتريات الاستلام الفعلي للمواد المرتجعة.',
    urduTitle: 'کمپنی مٹیریل واپسی کی تصدیق',
    urduBody: 'پروکیورمنٹ نے واپس کیے گئے مٹیریل کی جسمانی وصولی کی تصدیق کی۔',
    hindiTitle: 'कंपनी सामग्री वापसी की पुष्टि',
    hindiBody: 'खरीद टीम ने लौटाई गई सामग्री की भौतिक प्राप्ति की पुष्टि की।',
  ),
  'company_material_request_return_submitted': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company material return awaiting confirmation',
    englishBody: 'Review the returned items and confirm physical receipt.',
    arabicTitle: 'مرتجع مواد الشركة بانتظار التأكيد',
    arabicBody: 'راجع المواد المرتجعة وأكد استلامها الفعلي.',
    urduTitle: 'کمپنی واپسی تصدیق کی منتظر',
    urduBody: 'واپس کی گئی اشیا کا جائزہ لے کر جسمانی وصولی کی تصدیق کریں۔',
    hindiTitle: 'कंपनी वापसी पुष्टि की प्रतीक्षा में',
    hindiBody: 'लौटी सामग्री की समीक्षा करें और भौतिक प्राप्ति की पुष्टि करें।',
  ),
  'company_material_request_return_rejected': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company material return rejected',
    englishBody: 'Open the request to review the reason.',
    arabicTitle: 'رُفض مرتجع مواد الشركة',
    arabicBody: 'افتح الطلب لمراجعة السبب.',
    urduTitle: 'کمپنی واپسی مسترد',
    urduBody: 'وجہ دیکھنے کے لیے درخواست کھولیں۔',
    hindiTitle: 'कंपनी वापसी अस्वीकृत',
    hindiBody: 'कारण देखने के लिए अनुरोध खोलें।',
  ),
  'company_material_request_remainder_withdrawn': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company remaining need withdrawn',
    englishBody: 'Open the request to review the remaining quantities.',
    arabicTitle: 'سُحب الاحتياج المتبقي للشركة',
    arabicBody: 'افتح الطلب لمراجعة الكميات المتبقية.',
    urduTitle: 'کمپنی باقی ضرورت واپس لی گئی',
    urduBody: 'باقی مقدار دیکھنے کے لیے درخواست کھولیں۔',
    hindiTitle: 'कंपनी शेष आवश्यकता वापस ली गई',
    hindiBody: 'शेष मात्रा देखने के लिए अनुरोध खोलें।',
  ),
  'company_material_request_cancelled': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Company request cancelled',
    englishBody: 'Open the request to review the cancellation reason.',
    arabicTitle: 'أُلغي طلب الشركة',
    arabicBody: 'افتح الطلب لمراجعة سبب الإلغاء.',
    urduTitle: 'کمپنی درخواست منسوخ',
    urduBody: 'منسوخی کی وجہ دیکھنے کے لیے درخواست کھولیں۔',
    hindiTitle: 'कंपनी अनुरोध रद्द',
    hindiBody: 'रद्द करने का कारण देखने के लिए अनुरोध खोलें।',
  ),
  'company_material_request_closed': YorksV1NotificationCopy(
    type: NotificationType.info,
    englishTitle: 'Company request closed',
    englishBody: 'The completed company material request was closed.',
    arabicTitle: 'تم إغلاق طلب الشركة',
    arabicBody: 'تم إغلاق طلب مواد الشركة المكتمل.',
    urduTitle: 'کمپنی درخواست بند ہو گئی',
    urduBody: 'مکمل کمپنی مٹیریل درخواست بند کر دی گئی۔',
    hindiTitle: 'कंपनी अनुरोध बंद हुआ',
    hindiBody: 'पूरा कंपनी सामग्री अनुरोध बंद कर दिया गया।',
  ),
  'material_request_approval_required': _requestApprovalRequired,
  'material_request_updated_for_approval': _requestApprovalRequired,
  'material_request_approved_for_arrangement': _requestApprovedForArrangement,
  'material_request_changes_requested': _requestChangesRequired,
  'material_request_mentioned': _requestMention,
  'material_request_work_assigned': _requestWorkAssigned,
  'team_chat_message': YorksV1NotificationCopy(
    type: NotificationType.info,
    englishTitle: 'New Team Chat message',
    englishBody: 'A conversation you participate in has a new message.',
    arabicTitle: 'رسالة جديدة في محادثة الفريق',
    arabicBody: 'توجد رسالة جديدة في محادثة تشارك فيها.',
    urduTitle: 'ٹیم چیٹ میں نیا پیغام',
    urduBody: 'آپ کی شریک گفتگو میں ایک نیا پیغام ہے۔',
    hindiTitle: 'टीम चैट में नया संदेश',
    hindiBody: 'आपकी बातचीत में एक नया संदेश आया है।',
  ),
  'team_chat_mention': YorksV1NotificationCopy(
    type: NotificationType.info,
    englishTitle: 'You were mentioned in Team Chat',
    englishBody: 'A teammate mentioned you in a conversation.',
    arabicTitle: 'تمت الإشارة إليك في محادثة الفريق',
    arabicBody: 'أشار إليك زميل في محادثة.',
    urduTitle: 'ٹیم چیٹ میں آپ کا ذکر ہوا',
    urduBody: 'ایک ساتھی نے گفتگو میں آپ کا ذکر کیا۔',
    hindiTitle: 'टीम चैट में आपका उल्लेख हुआ',
    hindiBody: 'एक साथी ने बातचीत में आपका उल्लेख किया।',
  ),
  'arrangement_ready_for_dispatch': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Materials ready for dispatch',
    englishBody: 'Procurement completed the approved arrangement.',
    arabicTitle: 'المواد جاهزة للصرف',
    arabicBody: 'أكملت المشتريات الترتيب المعتمد.',
    urduTitle: 'مٹیریل ڈسپیچ کے لیے تیار ہے',
    urduBody: 'پروکیورمنٹ نے منظور شدہ انتظام مکمل کر لیا ہے۔',
    hindiTitle: 'सामग्री डिस्पैच के लिए तैयार',
    hindiBody: 'खरीद ने स्वीकृत व्यवस्था पूरी कर ली है।',
  ),
  'arrangement_completed_unavailable': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'All items currently unavailable',
    englishBody:
        'Procurement can revise the arrangement, or an authorised reviewer can cancel the request.',
    arabicTitle: 'جميع البنود غير متاحة حالياً',
    arabicBody:
        'يمكن للمشتريات تعديل الترتيب أو يمكن للمراجع المخوّل إلغاء الطلب.',
    urduTitle: 'تمام آئٹمز فی الحال دستیاب نہیں',
    urduBody:
        'پروکیورمنٹ انتظام میں ترمیم کر سکتی ہے، یا مجاز جائزہ لینے والا درخواست منسوخ کر سکتا ہے۔',
    hindiTitle: 'सभी आइटम अभी अनुपलब्ध हैं',
    hindiBody:
        'खरीद व्यवस्था संशोधित कर सकती है, या अधिकृत समीक्षक अनुरोध रद्द कर सकता है।',
  ),
  'material_request_submitted': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'New material request',
    englishBody: 'A material request is ready for Procurement arrangement.',
    arabicTitle: 'طلب مواد جديد',
    arabicBody: 'طلب مواد جاهز لترتيب المشتريات.',
    urduTitle: 'نئی مٹیریل ریکویسٹ',
    urduBody: 'مٹیریل ریکویسٹ پروکیورمنٹ انتظام کے لیے تیار ہے۔',
    hindiTitle: 'नया सामग्री अनुरोध',
    hindiBody: 'सामग्री अनुरोध खरीद व्यवस्था के लिए तैयार है।',
  ),
  'arrangement_review_required': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Arrangement ready for review',
    englishBody:
        'Procurement submitted an arrangement for Engineering approval.',
    arabicTitle: 'الترتيب جاهز للمراجعة',
    arabicBody: 'قدمت المشتريات ترتيباً لاعتماد الهندسة.',
    urduTitle: 'انتظام جائزے کے لیے تیار',
    urduBody: 'پروکیورمنٹ نے انجینئرنگ منظوری کے لیے انتظام جمع کیا ہے۔',
    hindiTitle: 'व्यवस्था समीक्षा के लिए तैयार',
    hindiBody: 'खरीद ने इंजीनियरिंग अनुमोदन के लिए व्यवस्था भेजी है।',
  ),
  'arrangement_approved': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Arrangement approved',
    englishBody: 'The material request is ready for controlled dispatch.',
    arabicTitle: 'تم اعتماد الترتيب',
    arabicBody: 'طلب المواد جاهز للصرف المنضبط.',
    urduTitle: 'انتظام منظور ہو گیا',
    urduBody: 'مٹیریل ریکویسٹ کنٹرولڈ ڈسپیچ کے لیے تیار ہے۔',
    hindiTitle: 'व्यवस्था स्वीकृत',
    hindiBody: 'सामग्री अनुरोध नियंत्रित डिस्पैच के लिए तैयार है।',
  ),
  'arrangement_returned': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Arrangement returned',
    englishBody: 'Engineering returned the arrangement to Procurement.',
    arabicTitle: 'تمت إعادة الترتيب',
    arabicBody: 'أعادت الهندسة الترتيب إلى المشتريات.',
    urduTitle: 'انتظام واپس کر دیا گیا',
    urduBody: 'انجینئرنگ نے انتظام پروکیورمنٹ کو واپس کیا ہے۔',
    hindiTitle: 'व्यवस्था लौटाई गई',
    hindiBody: 'इंजीनियरिंग ने व्यवस्था खरीद को लौटा दी है।',
  ),
  'receipt_review_required': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Delivery ready for receipt review',
    englishBody: 'Dispatched materials are awaiting the project team review.',
    arabicTitle: 'التسليم جاهز لمراجعة الاستلام',
    arabicBody: 'المواد المصروفة بانتظار مراجعة فريق المشروع.',
    urduTitle: 'ڈیلیوری وصولی جائزے کے لیے تیار',
    urduBody: 'بھیجا گیا مواد پروجیکٹ ٹیم کے جائزے کا منتظر ہے۔',
    hindiTitle: 'डिलीवरी प्राप्ति समीक्षा के लिए तैयार',
    hindiBody: 'भेजी गई सामग्री परियोजना टीम की समीक्षा की प्रतीक्षा में है।',
  ),
  'receipt_review_confirmed': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Receipt review confirmed',
    englishBody: 'The project team recorded the delivered material condition.',
    arabicTitle: 'تم تأكيد مراجعة الاستلام',
    arabicBody: 'سجل فريق المشروع حالة المواد المسلمة.',
    urduTitle: 'وصولی جائزے کی تصدیق ہو گئی',
    urduBody: 'پروجیکٹ ٹیم نے موصولہ مواد کی حالت ریکارڈ کر دی ہے۔',
    hindiTitle: 'प्राप्ति समीक्षा की पुष्टि हुई',
    hindiBody: 'परियोजना टीम ने वितरित सामग्री की स्थिति दर्ज की है।',
  ),
  'material_return_submitted': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return submitted',
    englishBody:
        'A project material return is awaiting Procurement confirmation.',
    arabicTitle: 'تم تقديم مرتجع مواد',
    arabicBody: 'مرتجع مواد المشروع بانتظار تأكيد المشتريات.',
    urduTitle: 'مٹیریل ریٹرن جمع ہو گیا',
    urduBody: 'پروجیکٹ مٹیریل ریٹرن پروکیورمنٹ تصدیق کا منتظر ہے۔',
    hindiTitle: 'सामग्री वापसी जमा हुई',
    hindiBody: 'परियोजना सामग्री वापसी खरीद पुष्टि की प्रतीक्षा में है।',
  ),
  'material_return_approval_required': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return approval required',
    englishBody: 'A project material return is ready for Engineering review.',
    arabicTitle: 'مطلوب اعتماد مرتجع المواد',
    arabicBody: 'مرتجع مواد المشروع جاهز لمراجعة الهندسة.',
    urduTitle: 'مٹیریل ریٹرن کی منظوری درکار ہے',
    urduBody: 'پروجیکٹ مٹیریل ریٹرن انجینئرنگ جائزے کے لیے تیار ہے۔',
    hindiTitle: 'सामग्री वापसी अनुमोदन आवश्यक',
    hindiBody: 'परियोजना सामग्री वापसी इंजीनियरिंग समीक्षा के लिए तैयार है।',
  ),
  'material_return_approved': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return approved',
    englishBody: 'Engineering approved the material return for site dispatch.',
    arabicTitle: 'تم اعتماد مرتجع المواد',
    arabicBody: 'اعتمدت الهندسة مرتجع المواد للإرسال من الموقع.',
    urduTitle: 'مٹیریل ریٹرن منظور ہو گیا',
    urduBody:
        'انجینئرنگ نے سائٹ سے بھیجنے کے لیے مٹیریل ریٹرن منظور کر لیا ہے۔',
    hindiTitle: 'सामग्री वापसी स्वीकृत',
    hindiBody: 'इंजीनियरिंग ने साइट से भेजने के लिए सामग्री वापसी स्वीकृत की।',
  ),
  'material_return_returned_for_changes': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return changes required',
    englishBody: 'Engineering returned the material return with a reason.',
    arabicTitle: 'مطلوب تعديل مرتجع المواد',
    arabicBody: 'أعادت الهندسة مرتجع المواد مع السبب.',
    urduTitle: 'مٹیریل ریٹرن میں تبدیلی درکار ہے',
    urduBody: 'انجینئرنگ نے مٹیریل ریٹرن وجہ کے ساتھ واپس کیا ہے۔',
    hindiTitle: 'सामग्री वापसी में बदलाव आवश्यक',
    hindiBody: 'इंजीनियरिंग ने कारण सहित सामग्री वापसी लौटा दी।',
  ),
  'material_return_receipt_required': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Returned materials awaiting receipt',
    englishBody:
        'Dispatched return materials are ready for Procurement receipt.',
    arabicTitle: 'المواد المرتجعة بانتظار الاستلام',
    arabicBody: 'المواد المرتجعة المرسلة جاهزة لاستلام المشتريات.',
    urduTitle: 'واپس شدہ مواد وصولی کا منتظر ہے',
    urduBody: 'بھیجا گیا واپس شدہ مواد پروکیورمنٹ وصولی کے لیے تیار ہے۔',
    hindiTitle: 'लौटाई सामग्री प्राप्ति की प्रतीक्षा में',
    hindiBody: 'भेजी गई वापसी सामग्री खरीद प्राप्ति के लिए तैयार है।',
  ),
  'material_return_confirmed': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return confirmed',
    englishBody:
        'Procurement confirmed physical receipt of the returned material.',
    arabicTitle: 'تم تأكيد مرتجع المواد',
    arabicBody: 'أكدت المشتريات الاستلام الفعلي للمواد المرتجعة.',
    urduTitle: 'مٹیریل ریٹرن کی تصدیق ہو گئی',
    urduBody: 'پروکیورمنٹ نے واپس شدہ مواد کی فزیکل وصولی کی تصدیق کر دی ہے۔',
    hindiTitle: 'सामग्री वापसी की पुष्टि हुई',
    hindiBody: 'खरीद ने लौटाई गई सामग्री की भौतिक प्राप्ति की पुष्टि की।',
  ),
  'material_return_rejected': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return rejected',
    englishBody: 'Procurement returned the material return with a reason.',
    arabicTitle: 'تم رفض مرتجع المواد',
    arabicBody: 'أعادت المشتريات مرتجع المواد مع السبب.',
    urduTitle: 'مٹیریل ریٹرن مسترد ہو گیا',
    urduBody: 'پروکیورمنٹ نے مٹیریل ریٹرن وجہ کے ساتھ واپس کر دیا ہے۔',
    hindiTitle: 'सामग्री वापसी अस्वीकृत हुई',
    hindiBody: 'खरीद ने कारण सहित सामग्री वापसी लौटा दी।',
  ),
  'material_return_cancelled': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material return cancelled',
    englishBody: 'The material return was cancelled before warehouse receipt.',
    arabicTitle: 'تم إلغاء مرتجع المواد',
    arabicBody: 'تم إلغاء مرتجع المواد قبل استلام المستودع.',
    urduTitle: 'مٹیریل ریٹرن منسوخ ہو گیا',
    urduBody: 'مٹیریل ریٹرن گودام کی وصولی سے پہلے منسوخ کر دیا گیا۔',
    hindiTitle: 'सामग्री वापसी रद्द हुई',
    hindiBody: 'गोदाम प्राप्ति से पहले सामग्री वापसी रद्द कर दी गई।',
  ),
  'material_request_cancelled': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material request cancelled',
    englishBody:
        'The material request was cancelled and open work was released.',
    arabicTitle: 'تم إلغاء طلب المواد',
    arabicBody: 'تم إلغاء طلب المواد وتحرير العمل المفتوح.',
    urduTitle: 'مٹیریل ریکویسٹ منسوخ ہو گئی',
    urduBody: 'مٹیریل ریکویسٹ منسوخ کر کے کھلا کام جاری کر دیا گیا ہے۔',
    hindiTitle: 'सामग्री अनुरोध रद्द हुआ',
    hindiBody: 'सामग्री अनुरोध रद्द कर दिया गया और खुला कार्य मुक्त हुआ।',
  ),
  'material_request_closed': YorksV1NotificationCopy(
    type: NotificationType.request,
    englishTitle: 'Material request completed',
    englishBody: 'The received material request was closed.',
    arabicTitle: 'اكتمل طلب المواد',
    arabicBody: 'تم إغلاق طلب المواد المستلم.',
    urduTitle: 'مٹیریل ریکویسٹ مکمل ہو گئی',
    urduBody: 'موصولہ مٹیریل ریکویسٹ بند کر دی گئی ہے۔',
    hindiTitle: 'सामग्री अनुरोध पूरा हुआ',
    hindiBody: 'प्राप्त सामग्री अनुरोध बंद कर दिया गया।',
  ),
  'project_member_assigned': YorksV1NotificationCopy(
    type: NotificationType.project,
    englishTitle: 'Project access assigned',
    englishBody: 'You were assigned to a Yorks project.',
    arabicTitle: 'تم تعيين صلاحية المشروع',
    arabicBody: 'تم تعيينك في مشروع يوركس.',
    urduTitle: 'پروجیکٹ رسائی تفویض ہو گئی',
    urduBody: 'آپ کو یورکس پروجیکٹ میں تفویض کیا گیا ہے۔',
    hindiTitle: 'परियोजना पहुंच सौंपी गई',
    hindiBody: 'आपको यॉर्क्स परियोजना में नियुक्त किया गया है।',
  ),
  'project_member_revoked': YorksV1NotificationCopy(
    type: NotificationType.project,
    englishTitle: 'Project access changed',
    englishBody: 'Your active assignment to a Yorks project ended.',
    arabicTitle: 'تم تغيير صلاحية المشروع',
    arabicBody: 'انتهى تعيينك النشط في مشروع يوركس.',
    urduTitle: 'پروجیکٹ رسائی تبدیل ہو گئی',
    urduBody: 'یورکس پروجیکٹ میں آپ کی فعال تفویض ختم ہو گئی ہے۔',
    hindiTitle: 'परियोजना पहुंच बदली गई',
    hindiBody: 'यॉर्क्स परियोजना में आपकी सक्रिय नियुक्ति समाप्त हुई।',
  ),
};
