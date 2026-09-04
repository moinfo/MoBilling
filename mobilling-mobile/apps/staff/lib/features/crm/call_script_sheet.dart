import 'package:flutter/material.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

// ─────────────────────────────────────────────────────────────────────────
// Call script — a read-only crib sheet, the mobile equivalent of the web's
// CallScriptDrawer. Content is bilingual (Swahili first, since that is the
// language most calls are actually made in) with `{name}` standing in for
// the caller's own name.
//
// Shared by the satisfaction-calls and follow-ups screens: both put the
// same "how do I open this call" reference behind a script button, and the
// content has no dependency on which queue opened it.
// ─────────────────────────────────────────────────────────────────────────

const Map<String, String> _scriptSw = {
  'tip':
      'Maneno yaliyoandikwa kwa herufi nzito yanasomwa kwa sauti kwa mteja. '
      'Badilisha [Jina la Mteja] na jina halisi la mteja.',
  's1': 'Sehemu 1: Mawasiliano Mapya',
  's1_answer_h': '📞 KUJIBU SIMU',
  's1_answer':
      'Habari za asubuhi/mchana/jioni! Asante kwa kupiga simu Moinfotech. '
      'Mimi ni {name}. Naweza kukusaidia vipi leo?',
  's1_call_h': '📲 KUPIGA SIMU — UTAMBULISHO',
  's1_call':
      'Habari! Ninaomba kuzungumza na [Jina la Mteja]. Mimi ni {name} '
      'kutoka Moinfotech.',
  's1_services_h': '📋 MAELEZO YA HUDUMA',
  's1_services':
      'Moinfotech ni kampuni ya teknolojia inayosaidia biashara kukua. '
      'Kauli mbiu yetu ni "Making Technology work for you". Tunatoa huduma '
      'mbalimbali: uwekaji wa tovuti na usajili wa domain, utengenezaji wa '
      'tovuti za kisasa, mifumo maalum (POS, Hotel, School, SACCO, HR, '
      'E-commerce na zaidi ya 50+), jukwaa la SMS nyingi, programu za simu, '
      'na msaada wa kiufundi wakati wowote.',
  's1_close_h': '✅ MWISHO WA MAZUNGUMZO',
  's1_close':
      'Ahsante sana [Jina la Mteja] kwa muda wako. Ikiwa una swali lolote, '
      'usisite kutupigia. Uwe na siku njema!',
  's2': 'Sehemu 2: Simu ya Ufuatiliaji',
  's2_follow_h': '🔄 SIMU YA UFUATILIAJI',
  's2_follow':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia kufuatilia mazungumzo yetu ya awali kuhusu huduma zetu. Je, '
      'umepata nafasi ya kufikiria?',
  's2_tip':
      'Sikiliza kwa makini jibu la mteja. Ikiwa ana maswali, jibu kwa upole '
      'na uwazi.',
  's2_happy_h': '😊 MTEJA AMERIDHIKA',
  's2_happy':
      'Tunafurahi sana kusikia hivyo! Ikiwa kuna jambo lingine tunaloweza '
      'kukusaidia, tuko tayari wakati wowote.',
  's2_issue_h': '😟 MTEJA ANA TATIZO',
  's2_issue':
      'Pole sana kwa usumbufu huo. Naelewa jinsi linavyokusumbua. Hebu '
      'nieleze tatizo lako ili niweze kukusaidia vizuri zaidi.',
  's3': 'Sehemu 3: Kukusanya Malipo',
  's3_remind_h': '💰 KUKUMBUSHA MALIPO',
  's3_remind':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia kukumbusha kuhusu invoice yako ambayo inafikia tarehe ya '
      'kulipa hivi karibuni. Je, umepata nafasi ya kulipa?',
  's3_late_h': '⏰ MALIPO YAMECHELEWA',
  's3_late':
      'Habari [Jina la Mteja]. Mimi ni {name} kutoka Moinfotech. '
      'Tunaona invoice yako bado haijalipwa na imepita tarehe yake. Je, '
      'kuna changamoto yoyote tunayoweza kukusaidia?',
  's3_tip':
      'Ikiwa mteja anaomba muda zaidi, panga tarehe mpya ya malipo na weka '
      'kwenye mfumo.',
  's3_overdue_h': '🔴 MALIPO YA MUDA MREFU (OVERDUE)',
  's3_overdue':
      'Habari [Jina la Mteja]. Mimi ni {name} kutoka Moinfotech. Invoice '
      'yako imechelewa kwa muda mrefu sasa. Tunataka kukusaidia kupanga '
      'malipo ili huduma zako ziendelee bila usumbufu.',
  's4': 'Sehemu 4: Msaada wa Kiufundi',
  's4_receive_h': '🔧 KUPOKEA TATIZO',
  's4_receive':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. Pole '
      'kwa tatizo unalokutana nalo. Hebu nieleze zaidi ili tuweze '
      'kukusaidia.',
  's4_diag_h': '🔍 MASWALI YA TATIZO',
  's4_diag':
      'Je, tatizo hili lilianza lini? Je, umejaribu kuzima na kuwasha '
      'tena? Je, tatizo linaathiri vifaa vyote au kimoja tu?',
  's4_tip': 'Sikiliza jibu kwa makini. Andika maelezo yote kwenye mfumo.',
  's4_resolve_h': '✅ HATUA ZA SULUHISHO',
  's4_resolve':
      'Sawa [Jina la Mteja], kulingana na maelezo yako, nitapeleka tatizo '
      'hili kwa timu yetu ya kiufundi. Watakuwasiliana ndani ya masaa 24.',
  's4_escalate_h': '🔁 ESCALATION',
  's4_escalate':
      'Pole sana [Jina la Mteja]. Tatizo hili linahitaji msaada wa '
      'ziada. Nitawasilisha kwa timu yetu maalum na watakupigia simu haraka '
      'iwezekanavyo.',
  's5': 'Sehemu 5: Simu za Kuridhika kwa Mteja',
  's5_goal':
      'Kupiga simu kwa mteja kila mwezi kujua kuridhika kwake na huduma '
      'zetu, kurekodi matatizo, na kupanga ziara za ana kwa ana '
      'inapohitajika.',
  's5_1_h': '📞 SIMU YA KURIDHIKA — UTANGULIZI',
  's5_1_intro':
      'Habari [Jina la Mteja]! Mimi ni {name} kutoka Moinfotech. '
      'Nakupigia simu yetu ya kila mwezi ya kuridhika kwa mteja. Je, una '
      'dakika chache tuzungumze kuhusu huduma zetu?',
  's5_1_cont':
      'Ahsante! Tunataka kujua jinsi unavyojisikia kuhusu huduma zetu na '
      'ikiwa kuna jambo lolote tunaloweza kuboresha.',
  's5_2_h': '⭐ KIWANGO CHA KURIDHIKA (1-5)',
  's5_2_ask':
      'Kwa kiwango cha 1 hadi 5, ambapo 1 ni mbaya sana na 5 ni bora sana, '
      'unaweza kutupa kiwango gani kwa huduma zetu?',
  's5_2_why': 'Ahsante! Je, kuna sababu maalum ya kiwango hicho?',
  's5_2_tip':
      'Andika kiwango (rating) kwenye mfumo mara moja. Ikiwa mteja '
      'amesita, msaidie kwa kutoa mifano.',
  's5_3_sat_h': '😊 MTEJA AMERIDHIKA',
  's5_3_sat':
      'Tunafurahi sana kusikia hivyo! Maoni yako mazuri yanatuhamasisha '
      'kuendelea kutoa huduma bora. Je, kuna pendekezo lolote la kuboresha '
      'zaidi?',
  's5_3_imp_h': '🔧 MAPENDEKEZO YA KUBORESHA',
  's5_3_imp':
      'Ahsante kwa uaminifu wako. Pendekezo lako ni muhimu sana kwetu. '
      'Nitaliandika na timu yetu italifanyia kazi.',
  's5_3_comp_h': '😟 MALALAMIKO',
  's5_3_comp':
      'Pole sana kwa usumbufu huo. Naelewa jinsi hilo linavyokusumbua. '
      'Nitaliandika malalamiko yako na timu yetu itakuwasiliana haraka '
      'iwezekanavyo.',
  's5_3_sug_h': '💡 WAZO/PENDEKEZO',
  's5_3_sug':
      'Ahsante kwa wazo hilo! Tunapenda kupokea maoni ya wateja wetu. '
      'Nitaliandika na kulipeleka kwa timu husika.',
  's5_4_h': '📍 KUOMBA ZIARA YA MTEJA',
  's5_4_ask':
      'Kwa sababu ya suala hili, tungependa kupanga ziara ya ana kwa ana '
      'ili tuweze kusaidia vizuri zaidi. Je, kuna siku na wakati unaofaa '
      'kwako?',
  's5_4_confirm':
      'Sawa, nimepanga ziara yako tarehe [Tarehe]. Mtu wetu atakuja '
      'kukutembelea. Je, kuna maelezo mengine ya ziara?',
  's5_4_decline':
      'Hakuna shida. Ikiwa utabadilisha mawazo yako, tuko tayari '
      'kukusaidia wakati wowote.',
  's5_4_tip':
      'Pendekeza ziara kwa malalamiko makubwa au matatizo ya kiufundi '
      'ambayo hayawezi kutatuliwa kwa simu.',
  's5_5_h': '📵 MTEJA HAJAJIBU / HAFIKIKI',
  's5_5_step1': 'Jaribu mara 2-3 kwa nyakati tofauti.',
  's5_5_step2':
      'Ikiwa bado hajibu, rekodi kwenye mfumo: outcome = no_answer au '
      'unreachable — mfumo utapanga simu ya ufuatiliaji siku ya kazi '
      'inayofuata.',
  's5_6_h': '✅ MWISHO WA SIMU YA KURIDHIKA',
  's5_6_close':
      'Ahsante sana [Jina la Mteja] kwa muda wako na maoni yako. Maoni '
      'yako yanasaidia sana kuboresha huduma zetu. Tutaendelea kukupigia '
      'simu kila mwezi kujua hali yako.',
  's5_6_appt':
      'Na kumbuka, timu yetu itakuja kukutembelea tarehe [Tarehe]. '
      'Tutakutumia ujumbe wa kukumbushia.',
  'qr_angry': 'Mteja anakasirika',
  'qr_angry_say': 'Naelewa frustration yako. Hili ni muhimu kwetu pia.',
  'qr_dunno': 'Hujui jibu',
  'qr_dunno_say': 'Naomba dakika moja tu. Nataka kukupa jibu sahihi.',
  'qr_mgr': 'Mteja anataka msimamizi',
  'qr_mgr_say': 'Nakuelewa. Nitamwita msimamizi wangu sasa hivi.',
  'qr_sat': 'Mteja ameridhika (simu ya kuridhika)',
  'qr_sat_say': 'Tunafurahi sana kusikia hivyo! Kiwango chako ni muhimu kwetu.',
  'qr_prob': 'Mteja ana tatizo (simu ya kuridhika)',
  'qr_prob_say':
      'Pole sana. Nitaliandika na timu yetu italifanyia kazi haraka.',
  'qr_visit': 'Kuomba ziara',
  'qr_visit_say':
      'Tungependa kupanga ziara ili tuweze kusaidia vizuri zaidi.',
  'qr_end': 'Kumalizia mazungumzo',
  'qr_end_say': 'Asante kwa muda wako [Jina la Mteja]. Uwe na siku njema!',
};

const Map<String, String> _scriptEn = {
  'tip':
      'Words written in bold are read aloud to the client. Replace '
      '[Client Name] with the actual client name.',
  's1': 'Section 1: New Contact',
  's1_answer_h': '📞 ANSWERING A CALL',
  's1_answer':
      'Good morning/afternoon/evening! Thank you for calling Moinfotech. '
      'My name is {name}. How can I help you today?',
  's1_call_h': '📲 MAKING A CALL — INTRODUCTION',
  's1_call':
      'Hello! May I speak with [Client Name]? My name is {name} from '
      'Moinfotech.',
  's1_services_h': '📋 SERVICE DESCRIPTION',
  's1_services':
      'Moinfotech is a technology company that helps businesses grow. Our '
      'motto is "Making Technology work for you". We offer hosting and '
      'domain registration, modern responsive websites, custom systems '
      '(POS, Hotel, School, SACCO, HR, E-commerce and 50+ more), bulk SMS, '
      'mobile apps, and technical support anytime.',
  's1_close_h': '✅ CLOSING THE CONVERSATION',
  's1_close':
      'Thank you very much [Client Name] for your time. If you have any '
      'questions, do not hesitate to call us. Have a great day!',
  's2': 'Section 2: Follow-up Call',
  's2_follow_h': '🔄 FOLLOW-UP CALL',
  's2_follow':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling to follow up on our previous conversation about our '
      'services. Have you had a chance to think about it?',
  's2_tip':
      'Listen carefully to the client\'s response. If they have '
      'questions, answer politely and clearly.',
  's2_happy_h': '😊 CLIENT IS SATISFIED',
  's2_happy':
      'We are very happy to hear that! If there is anything else we can '
      'help you with, we are ready anytime.',
  's2_issue_h': '😟 CLIENT HAS AN ISSUE',
  's2_issue':
      'We are very sorry for the inconvenience. I understand how it '
      'affects you. Please explain the issue so I can help you better.',
  's3': 'Section 3: Payment Collection',
  's3_remind_h': '💰 PAYMENT REMINDER',
  's3_remind':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling to remind you about your invoice that is approaching its '
      'due date. Have you had a chance to make the payment?',
  's3_late_h': '⏰ LATE PAYMENT',
  's3_late':
      'Hello [Client Name]. My name is {name} from Moinfotech. We '
      'notice your invoice is still unpaid and past its due date. Is '
      'there any challenge we can help you with?',
  's3_tip':
      'If the client asks for more time, schedule a new payment date and '
      'record it in the system.',
  's3_overdue_h': '🔴 LONG OVERDUE PAYMENT',
  's3_overdue':
      'Hello [Client Name]. My name is {name} from Moinfotech. Your '
      'invoice has been overdue for a long time now. We want to help you '
      'arrange payment so your services continue without interruption.',
  's4': 'Section 4: Technical Support',
  's4_receive_h': '🔧 RECEIVING AN ISSUE',
  's4_receive':
      'Hello [Client Name]! My name is {name} from Moinfotech. Sorry '
      'about the issue you\'re experiencing. Please tell me more so we '
      'can help you.',
  's4_diag_h': '🔍 DIAGNOSTIC QUESTIONS',
  's4_diag':
      'When did this issue start? Have you tried turning it off and on '
      'again? Does the issue affect all devices or just one?',
  's4_tip': 'Listen carefully to the answer. Record all details in the system.',
  's4_resolve_h': '✅ RESOLUTION STEPS',
  's4_resolve':
      'Okay [Client Name], based on your description, I will escalate '
      'this issue to our technical team. They will contact you within 24 '
      'hours.',
  's4_escalate_h': '🔁 ESCALATION',
  's4_escalate':
      'We are very sorry [Client Name]. This issue requires additional '
      'support. I will forward it to our specialized team and they will '
      'call you as soon as possible.',
  's5': 'Section 5: Satisfaction Calls',
  's5_goal':
      'Call each client monthly to assess their satisfaction with our '
      'services, record any issues, and schedule in-person visits when '
      'needed.',
  's5_1_h': '📞 SATISFACTION CALL — INTRODUCTION',
  's5_1_intro':
      'Hello [Client Name]! My name is {name} from Moinfotech. I\'m '
      'calling for our monthly customer satisfaction check-in. Do you '
      'have a few minutes to talk about our services?',
  's5_1_cont':
      'Thank you! We want to know how you feel about our services and if '
      'there is anything we can improve.',
  's5_2_h': '⭐ SATISFACTION RATING (1-5)',
  's5_2_ask':
      'On a scale of 1 to 5, where 1 is very poor and 5 is excellent, '
      'how would you rate our services?',
  's5_2_why': 'Thank you! Is there a specific reason for that rating?',
  's5_2_tip':
      'Record the rating in the system immediately. If the client '
      'hesitates, help them by giving examples.',
  's5_3_sat_h': '😊 CLIENT IS SATISFIED',
  's5_3_sat':
      'We are so happy to hear that! Your positive feedback motivates us '
      'to continue providing excellent service. Do you have any '
      'suggestions for improvement?',
  's5_3_imp_h': '🔧 NEEDS IMPROVEMENT',
  's5_3_imp':
      'Thank you for your honesty. Your suggestion is very important to '
      'us. I will record it and our team will work on it.',
  's5_3_comp_h': '😟 COMPLAINT',
  's5_3_comp':
      'We are very sorry for the inconvenience. I understand how '
      'frustrating that is. I will record your complaint and our team '
      'will get back to you as soon as possible.',
  's5_3_sug_h': '💡 IDEA/SUGGESTION',
  's5_3_sug':
      'Thank you for that idea! We love receiving feedback from our '
      'clients. I will record it and forward it to the relevant team.',
  's5_4_h': '📍 REQUESTING A CLIENT VISIT',
  's5_4_ask':
      'Because of this issue, we would like to schedule an in-person '
      'visit so we can help you better. Is there a day and time that '
      'works for you?',
  's5_4_confirm':
      'Great, I have scheduled your visit for [Date]. Our representative '
      'will come to see you. Are there any other details about the '
      'visit?',
  's5_4_decline':
      'No problem. If you change your mind, we are ready to help you '
      'anytime.',
  's5_4_tip':
      'Suggest visits for serious complaints or technical issues that '
      'cannot be resolved over the phone.',
  's5_5_h': '📵 NO ANSWER / UNREACHABLE',
  's5_5_step1': 'Try 2-3 times at different times.',
  's5_5_step2':
      'If still no answer, record in system: outcome = no_answer or '
      'unreachable — the follow-up call will appear on your schedule the '
      'next business day.',
  's5_6_h': '✅ END OF SATISFACTION CALL',
  's5_6_close':
      'Thank you so much [Client Name] for your time and feedback. Your '
      'feedback helps us greatly improve our services. We will continue '
      'calling you monthly to check in.',
  's5_6_appt':
      'And remember, our team will come to visit you on [Date]. We will '
      'send you a reminder message.',
  'qr_angry': 'Client is angry',
  'qr_angry_say': 'I understand your frustration. This is important to us too.',
  'qr_dunno': 'You don\'t know the answer',
  'qr_dunno_say': 'Just a moment please. I want to give you the right answer.',
  'qr_mgr': 'Client wants a manager',
  'qr_mgr_say': 'I understand. Let me get my supervisor right away.',
  'qr_sat': 'Client is satisfied (satisfaction call)',
  'qr_sat_say': 'We are so happy to hear that! Your rating is very important to us.',
  'qr_prob': 'Client has a problem (satisfaction call)',
  'qr_prob_say': 'We are very sorry. I will record it and our team will work on it quickly.',
  'qr_visit': 'Requesting a visit',
  'qr_visit_say': 'We would like to schedule a visit so we can help you better.',
  'qr_end': 'Closing the conversation',
  'qr_end_say': 'Thank you for your time [Client Name]. Have a great day!',
};

/// The customer-care call script — opened as a bottom sheet from both the
/// satisfaction-calls and follow-ups screens (mirroring the web's shared
/// `CallScriptDrawer`).
class CallScriptSheet extends StatefulWidget {
  const CallScriptSheet({super.key, required this.agentName});

  final String agentName;

  @override
  State<CallScriptSheet> createState() => _CallScriptSheetState();
}

class _CallScriptSheetState extends State<CallScriptSheet> {
  bool _swahili = true;

  String _t(String key) {
    final t = _swahili ? _scriptSw : _scriptEn;
    return (t[key] ?? '').replaceAll('{name}', widget.agentName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          sheetBottomInset(context) + Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Customer care call script',
              style: Type.display(20, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('🇹🇿 Swahili')),
                ButtonSegment(value: false, label: Text('🇬🇧 English')),
              ],
              selected: {_swahili},
              onSelectionChanged: (s) => setState(() => _swahili = s.first),
            ),
            const SizedBox(height: Spacing.md),
            Expanded(
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    margin: const EdgeInsets.only(bottom: Spacing.md),
                    decoration: BoxDecoration(
                      color: status.pending.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text('💡 ${_t('tip')}', style: theme.textTheme.bodySmall),
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.call_outlined,
                    title: _t('s1'),
                    children: [
                      _block(context, _t('s1_answer_h'), _t('s1_answer')),
                      _block(context, _t('s1_call_h'), _t('s1_call')),
                      _block(context, _t('s1_services_h'), _t('s1_services')),
                      _block(context, _t('s1_close_h'), _t('s1_close')),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.repeat_outlined,
                    title: _t('s2'),
                    children: [
                      _block(context, _t('s2_follow_h'), _t('s2_follow')),
                      _tip(context, _t('s2_tip')),
                      _block(
                        context,
                        _t('s2_happy_h'),
                        _t('s2_happy'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s2_issue_h'),
                        _t('s2_issue'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.receipt_long_outlined,
                    title: _t('s3'),
                    children: [
                      _block(context, _t('s3_remind_h'), _t('s3_remind')),
                      _block(
                        context,
                        _t('s3_late_h'),
                        _t('s3_late'),
                        color: status.attention,
                      ),
                      _tip(context, _t('s3_tip')),
                      _block(
                        context,
                        _t('s3_overdue_h'),
                        _t('s3_overdue'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.build_outlined,
                    title: _t('s4'),
                    children: [
                      _block(context, _t('s4_receive_h'), _t('s4_receive')),
                      _block(context, _t('s4_diag_h'), _t('s4_diag')),
                      _tip(context, _t('s4_tip')),
                      _block(
                        context,
                        _t('s4_resolve_h'),
                        _t('s4_resolve'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s4_escalate_h'),
                        _t('s4_escalate'),
                        color: status.overdue,
                      ),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.favorite_outline,
                    title: _t('s5'),
                    initiallyExpanded: true,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(Spacing.sm),
                        margin: const EdgeInsets.only(bottom: Spacing.sm),
                        decoration: BoxDecoration(
                          color: status.settled.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Text(_t('s5_goal'), style: theme.textTheme.bodySmall),
                      ),
                      _block(context, _t('s5_1_h'), _t('s5_1_intro')),
                      _block(context, '', _t('s5_1_cont')),
                      _block(context, _t('s5_2_h'), _t('s5_2_ask')),
                      _block(context, '', _t('s5_2_why')),
                      _tip(context, _t('s5_2_tip')),
                      _block(
                        context,
                        _t('s5_3_sat_h'),
                        _t('s5_3_sat'),
                        color: status.settled,
                      ),
                      _block(
                        context,
                        _t('s5_3_imp_h'),
                        _t('s5_3_imp'),
                        color: status.attention,
                      ),
                      _block(
                        context,
                        _t('s5_3_comp_h'),
                        _t('s5_3_comp'),
                        color: status.overdue,
                      ),
                      _block(
                        context,
                        _t('s5_3_sug_h'),
                        _t('s5_3_sug'),
                        color: status.pending,
                      ),
                      _block(context, _t('s5_4_h'), _t('s5_4_ask')),
                      _block(context, '', _t('s5_4_confirm')),
                      _block(context, '', _t('s5_4_decline')),
                      _tip(context, _t('s5_4_tip')),
                      _block(
                        context,
                        _t('s5_5_h'),
                        '${_t('s5_5_step1')}\n${_t('s5_5_step2')}',
                      ),
                      _block(context, _t('s5_6_h'), _t('s5_6_close')),
                      _block(context, '', _t('s5_6_appt')),
                    ],
                  ),
                  _scriptSection(
                    context,
                    icon: Icons.star_outline,
                    title: _swahili ? 'Jedwali la Kumbukumbu' : 'Quick Reference',
                    children: [
                      for (final key in [
                        'angry',
                        'dunno',
                        'mgr',
                        'sat',
                        'prob',
                        'visit',
                        'end',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t('qr_$key'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '"${_t('qr_${key}_say')}"',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _scriptSection(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> children,
  bool initiallyExpanded = false,
}) => Card(
  clipBehavior: Clip.antiAlias,
  margin: const EdgeInsets.only(bottom: Spacing.sm),
  child: ExpansionTile(
    leading: Icon(icon),
    title: Text(title, style: Theme.of(context).textTheme.titleSmall),
    initiallyExpanded: initiallyExpanded,
    childrenPadding: const EdgeInsets.fromLTRB(
      Spacing.md,
      0,
      Spacing.md,
      Spacing.md,
    ),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
);

Widget _block(
  BuildContext context,
  String heading,
  String body, {
  Color? color,
}) {
  final theme = Theme.of(context);
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: Spacing.sm),
    padding: const EdgeInsets.all(Spacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: theme.colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading.isNotEmpty) ...[
          Text(
            heading,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color ?? context.statusColors.pending,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(body, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}

Widget _tip(BuildContext context, String text) {
  final status = context.statusColors;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: Spacing.sm),
    padding: const EdgeInsets.all(Spacing.sm),
    decoration: BoxDecoration(
      color: status.attention.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Text('💡 $text', style: Theme.of(context).textTheme.bodySmall),
  );
}
