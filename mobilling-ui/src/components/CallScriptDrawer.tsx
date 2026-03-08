import { useState } from 'react';
import {
  Text, Group, Badge, Table, Paper, Stack, Drawer,
  Accordion, List, SegmentedControl,
} from '@mantine/core';
import {
  IconHeartHandshake, IconAlertTriangle, IconPhone,
  IconFileInvoice, IconRepeat, IconStar, IconScript,
} from '@tabler/icons-react';

// Call script translations (Swahili / English)
const script = {
  sw: {
    tip: 'Maneno yaliyoandikwa kwa **bold** yanasomwa kwa sauti kwa mteja. Badilisha [Jina la Mteja] na jina halisi la mteja.',
    s1: 'Sehemu 1: Mawasiliano Mapya',
    s1_answer_h: '📞 KUJIBU SIMU',
    s1_answer: (n: string) => `Habari za asubuhi/mchana/jioni! Asante kwa kupiga simu Moinfotech. Mimi ni ${n}. Naweza kukusaidia vipi leo?`,
    s1_call_h: '📲 KUPIGA SIMU — UTAMBULISHO',
    s1_call: (n: string) => `Habari! Ninaomba kuzungumza na [Jina la Mteja]. Mimi ni ${n} kutoka Moinfotech.`,
    s1_services_h: '📋 MAELEZO YA HUDUMA',
    s1_services: 'Moinfotech ni kampuni ya teknolojia inayosaidia biashara kukua. Kauli mbiu yetu ni "Making Technology work for you". Tunatoa huduma mbalimbali:',
    s1_svc_hosting: 'Tunaweka tovuti na kusajili domain (.co.tz, .com)',
    s1_svc_web: 'Tunatengeneza tovuti za kisasa na responsive',
    s1_svc_systems: 'POS, Hotel, School, SACCO, HR, E-commerce, na zaidi (50+ systems)',
    s1_svc_sms: 'Jukwaa la kutuma SMS nyingi kwa wateja',
    s1_svc_apps: 'Programu za simu kwa biashara',
    s1_svc_support: 'Msaada wa kiufundi wakati wowote',
    s1_close_h: '✅ MWISHO WA MAZUNGUMZO',
    s1_close: 'Ahsante sana [Jina la Mteja] kwa muda wako. Ikiwa una swali lolote, usisite kutupigia. Uwe na siku njema!',
    s2: 'Sehemu 2: Simu ya Ufuatiliaji',
    s2_follow_h: '🔄 SIMU YA UFUATILIAJI',
    s2_follow: (n: string) => `Habari [Jina la Mteja]! Mimi ni ${n} kutoka Moinfotech. Nakupigia kufuatilia mazungumzo yetu ya awali kuhusu huduma zetu. Je, umepata nafasi ya kufikiria?`,
    s2_tip: 'Sikiliza kwa makini jibu la mteja. Ikiwa ana maswali, jibu kwa upole na uwazi.',
    s2_happy_h: '😊 MTEJA AMERIDHIKA',
    s2_happy: 'Tunafurahi sana kusikia hivyo! Ikiwa kuna jambo lingine tunaloweza kukusaidia, tuko tayari wakati wowote.',
    s2_issue_h: '😟 MTEJA ANA TATIZO',
    s2_issue: 'Pole sana kwa usumbufu huo. Naelewa jinsi linavyokusumbua. Hebu nieleze tatizo lako ili niweze kukusaidia vizuri zaidi.',
    s3: 'Sehemu 3: Kukusanya Malipo',
    s3_remind_h: '💰 KUKUMBUSHA MALIPO',
    s3_remind: (n: string) => `Habari [Jina la Mteja]! Mimi ni ${n} kutoka Moinfotech. Nakupigia kukumbusha kuhusu invoice yako ambayo inafikia tarehe ya kulipa hivi karibuni. Je, umepata nafasi ya kulipa?`,
    s3_late_h: '⏰ MALIPO YAMECHELEWA',
    s3_late: (n: string) => `Habari [Jina la Mteja]. Mimi ni ${n} kutoka Moinfotech. Tunaona invoice yako bado haijalipwa na imepita tarehe yake. Je, kuna changamoto yoyote tunayoweza kukusaidia?`,
    s3_tip: 'Ikiwa mteja anaomba muda zaidi, panga tarehe mpya ya malipo na weka kwenye mfumo.',
    s3_overdue_h: '🔴 MALIPO YA MUDA MREFU (OVERDUE)',
    s3_overdue: (n: string) => `Habari [Jina la Mteja]. Mimi ni ${n} kutoka Moinfotech. Invoice yako imechelewa kwa muda mrefu sasa. Tunataka kukusaidia kupanga malipo ili huduma zako ziendelee bila usumbufu.`,
    s4: 'Sehemu 4: Msaada wa Kiufundi',
    s4_receive_h: '🔧 KUPOKEA TATIZO',
    s4_receive: (n: string) => `Habari [Jina la Mteja]! Mimi ni ${n} kutoka Moinfotech. Pole kwa tatizo unalokutana nalo. Hebu nieleze zaidi ili tuweze kukusaidia.`,
    s4_diag_h: '🔍 MASWALI YA TATIZO',
    s4_diag: 'Je, tatizo hili lilianza lini? Je, umejaribu kuzima na kuwasha tena? Je, tatizo linaathiri vifaa vyote au kimoja tu?',
    s4_tip: 'Sikiliza jibu kwa makini. Andika maelezo yote kwenye mfumo.',
    s4_resolve_h: '✅ HATUA ZA SULUHISHO',
    s4_resolve: 'Sawa [Jina la Mteja], kulingana na maelezo yako, nitapeleka tatizo hili kwa timu yetu ya kiufundi. Watakuwasiliana ndani ya masaa 24.',
    s4_escalate_h: '🔁 ESCALATION',
    s4_escalate: 'Pole sana [Jina la Mteja]. Tatizo hili linahitaji msaada wa ziada. Nitawasilisha kwa timu yetu maalum na watakupigia simu haraka iwezekanavyo.',
    s5: 'Sehemu 5: Simu za Kuridhika kwa Mteja (Satisfaction Calls)',
    s5_goal: 'Kupiga simu kwa mteja kila mwezi kujua kuridhika kwake na huduma zetu, kurekodi matatizo, na kupanga ziara za ana kwa ana inapohitajika.',
    s5_1: '5.1 KUFUNGUA MAZUNGUMZO', s5_1_h: '📞 SIMU YA KURIDHIKA — UTANGULIZI',
    s5_1_intro: (n: string) => `Habari [Jina la Mteja]! Mimi ni ${n} kutoka Moinfotech. Nakupigia simu yetu ya kila mwezi ya kuridhika kwa mteja. Je, una dakika chache tuzungumze kuhusu huduma zetu?`,
    s5_1_if: '[Ikiwa mteja ana muda]',
    s5_1_cont: 'Ahsante! Tunataka kujua jinsi unavyojisikia kuhusu huduma zetu na ikiwa kuna jambo lolote tunaloweza kuboresha.',
    s5_2: '5.2 KUULIZA KUHUSU HUDUMA (RATING)', s5_2_h: '⭐ KIWANGO CHA KURIDHIKA (1-5)',
    s5_2_ask: 'Kwa kiwango cha 1 hadi 5, ambapo 1 ni mbaya sana na 5 ni bora sana, unaweza kutupa kiwango gani kwa huduma zetu?',
    s5_2_r1: '⭐ 1 = Mbaya sana', s5_2_r2: '⭐⭐ 2 = Mbaya', s5_2_r3: '⭐⭐⭐ 3 = Wastani',
    s5_2_r4: '⭐⭐⭐⭐ 4 = Nzuri', s5_2_r5: '⭐⭐⭐⭐⭐ 5 = Bora sana',
    s5_2_why: 'Ahsante! Je, kuna sababu maalum ya kiwango hicho?',
    s5_2_tip: 'Andika kiwango (rating) kwenye mfumo mara moja. Ikiwa mteja amesita, msaidie kwa kutoa mifano.',
    s5_3: '5.3 KUREKODI MATOKEO',
    s5_3_sat_h: '😊 MTEJA AMERIDHIKA (Satisfied)', s5_3_sat: 'Tunafurahi sana kusikia hivyo! Maoni yako mazuri yanatuhamasisha kuendelea kutoa huduma bora. Je, kuna pendekezo lolote la kuboresha zaidi?',
    s5_3_sat_note: '[Rekodi: outcome = satisfied, rating, na feedback yoyote]',
    s5_3_imp_h: '🔧 MAPENDEKEZO YA KUBORESHA (Needs Improvement)', s5_3_imp: 'Ahsante kwa uaminifu wako. Pendekezo lako ni muhimu sana kwetu. Nitaliandika na timu yetu italifanyia kazi.',
    s5_3_imp_note: '[Rekodi: outcome = needs_improvement, rating, na maelezo kamili]',
    s5_3_comp_h: '😟 MALALAMIKO (Complaint)', s5_3_comp: 'Pole sana kwa usumbufu huo. Naelewa jinsi hilo linavyokusumbua. Nitaliandika malalamiko yako na timu yetu itakuwasiliana haraka iwezekanavyo.',
    s5_3_comp_note: '[Rekodi: outcome = complaint — pendekeza ziara ikiwa tatizo ni kubwa]',
    s5_3_sug_h: '💡 WAZO/PENDEKEZO (Suggestion)', s5_3_sug: 'Ahsante kwa wazo hilo! Tunapenda kupokea maoni ya wateja wetu. Nitaliandika na kulipeleka kwa timu husika.',
    s5_3_sug_note: '[Rekodi: outcome = suggestion, na maelezo ya pendekezo]',
    s5_4: '5.4 KUPANGA ZIARA YA ANA KWA ANA (APPOINTMENT)', s5_4_h: '📍 KUOMBA ZIARA YA MTEJA',
    s5_4_ask: 'Kwa sababu ya suala hili, tungependa kupanga ziara ya ana kwa ana ili tuweze kusaidia vizuri zaidi. Je, kuna siku na wakati unaofaa kwako?',
    s5_4_yes: '[Ikiwa mteja anakubali]', s5_4_confirm: 'Sawa, nimepanga ziara yako tarehe [Tarehe]. Mtu wetu atakuja kukutembelea. Je, kuna maelezo mengine ya ziara?',
    s5_4_rec: '[Rekodi kwenye mfumo: appointment_requested = Ndio, tarehe, na maelezo]',
    s5_4_no: '[Ikiwa mteja anakataa]', s5_4_decline: 'Hakuna shida. Ikiwa utabadilisha mawazo yako, tuko tayari kukusaidia wakati wowote.',
    s5_4_tip: 'Pendekeza ziara kwa malalamiko makubwa au matatizo ya kiufundi ambayo hayawezi kutatuliwa kwa simu.',
    s5_5: '5.5 MTEJA HAJIBU SIMU', s5_5_h: '📵 MTEJA HAJAJIBU / HAFIKIKI',
    s5_5_steps: ['Jaribu mara 2-3 kwa nyakati tofauti', 'Ikiwa bado hajibu, rekodi kwenye mfumo: outcome = no_answer au unreachable'],
    s5_5_auto: 'simu ya ufuatiliaji kiotomatiki', s5_5_s3: 'siku ya kazi inayofuata', s5_5_s4: 'Simu ya ufuatiliaji itaonyeshwa kwenye ratiba yako',
    s5_6: '5.6 KUMALIZIA MAZUNGUMZO', s5_6_h: '✅ MWISHO WA SIMU YA KURIDHIKA',
    s5_6_close: 'Ahsante sana [Jina la Mteja] kwa muda wako na maoni yako. Maoni yako yanasaidia sana kuboresha huduma zetu. Tutaendelea kukupigia simu kila mwezi kujua hali yako.',
    s5_6_if: '[Ikiwa kuna ziara iliyopangwa]', s5_6_appt: 'Na kumbuka, timu yetu itakuja kukutembelea tarehe [Tarehe]. Tutakutumia ujumbe wa kukumbushia.',
    s5_6_bye: 'Uwe na siku njema! Kwa msaada wowote, usisite kutupigia.',
    qr: 'Jedwali la Kumbukumbu (Quick Reference)', qr_sit: 'Hali', qr_say: 'Unachosema',
    qr_angry: 'Mteja anakasirika', qr_angry_say: 'Naelewa frustration yako. Hili ni muhimu kwetu pia.',
    qr_dunno: 'Hujui jibu', qr_dunno_say: 'Naomba dakika moja tu. Nataka kukupa jibu sahihi.',
    qr_mgr: 'Mteja anataka msimamizi', qr_mgr_say: 'Nakuelewa. Nitamwita msimamizi wangu sasa hivi.',
    qr_sat: 'Mteja ameridhika (simu ya kuridhika)', qr_sat_say: 'Tunafurahi sana kusikia hivyo! Kiwango chako ni muhimu kwetu.',
    qr_prob: 'Mteja ana tatizo (simu ya kuridhika)', qr_prob_say: 'Pole sana. Nitaliandika na timu yetu italifanyia kazi haraka.',
    qr_visit: 'Kuomba ziara', qr_visit_say: 'Tungependa kupanga ziara ili tuweze kusaidia vizuri zaidi.',
    qr_end: 'Kumalizia mazungumzo', qr_end_say: 'Asante kwa muda wako [Jina la Mteja]. Uwe na siku njema!',
    goal: 'Lengo',
  },
  en: {
    tip: 'Words written in **bold** are read aloud to the client. Replace [Client Name] with the actual client name.',
    s1: 'Section 1: New Contact',
    s1_answer_h: '📞 ANSWERING A CALL',
    s1_answer: (n: string) => `Good morning/afternoon/evening! Thank you for calling Moinfotech. My name is ${n}. How can I help you today?`,
    s1_call_h: '📲 MAKING A CALL — INTRODUCTION',
    s1_call: (n: string) => `Hello! May I speak with [Client Name]? My name is ${n} from Moinfotech.`,
    s1_services_h: '📋 SERVICE DESCRIPTION',
    s1_services: 'Moinfotech is a technology company that helps businesses grow. Our motto is "Making Technology work for you". We offer various services:',
    s1_svc_hosting: 'We host websites and register domains (.co.tz, .com)',
    s1_svc_web: 'We build modern, responsive websites',
    s1_svc_systems: 'POS, Hotel, School, SACCO, HR, E-commerce, and more (50+ systems)',
    s1_svc_sms: 'Platform for sending bulk SMS to clients',
    s1_svc_apps: 'Mobile applications for businesses',
    s1_svc_support: 'Technical support anytime',
    s1_close_h: '✅ CLOSING THE CONVERSATION',
    s1_close: 'Thank you very much [Client Name] for your time. If you have any questions, do not hesitate to call us. Have a great day!',
    s2: 'Section 2: Follow-up Call',
    s2_follow_h: '🔄 FOLLOW-UP CALL',
    s2_follow: (n: string) => `Hello [Client Name]! My name is ${n} from Moinfotech. I'm calling to follow up on our previous conversation about our services. Have you had a chance to think about it?`,
    s2_tip: 'Listen carefully to the client\'s response. If they have questions, answer politely and clearly.',
    s2_happy_h: '😊 CLIENT IS SATISFIED',
    s2_happy: 'We are very happy to hear that! If there is anything else we can help you with, we are ready anytime.',
    s2_issue_h: '😟 CLIENT HAS AN ISSUE',
    s2_issue: 'We are very sorry for the inconvenience. I understand how it affects you. Please explain the issue so I can help you better.',
    s3: 'Section 3: Payment Collection',
    s3_remind_h: '💰 PAYMENT REMINDER',
    s3_remind: (n: string) => `Hello [Client Name]! My name is ${n} from Moinfotech. I'm calling to remind you about your invoice that is approaching its due date. Have you had a chance to make the payment?`,
    s3_late_h: '⏰ LATE PAYMENT',
    s3_late: (n: string) => `Hello [Client Name]. My name is ${n} from Moinfotech. We notice your invoice is still unpaid and past its due date. Is there any challenge we can help you with?`,
    s3_tip: 'If the client asks for more time, schedule a new payment date and record it in the system.',
    s3_overdue_h: '🔴 LONG OVERDUE PAYMENT',
    s3_overdue: (n: string) => `Hello [Client Name]. My name is ${n} from Moinfotech. Your invoice has been overdue for a long time now. We want to help you arrange payment so your services continue without interruption.`,
    s4: 'Section 4: Technical Support',
    s4_receive_h: '🔧 RECEIVING AN ISSUE',
    s4_receive: (n: string) => `Hello [Client Name]! My name is ${n} from Moinfotech. Sorry about the issue you're experiencing. Please tell me more so we can help you.`,
    s4_diag_h: '🔍 DIAGNOSTIC QUESTIONS',
    s4_diag: 'When did this issue start? Have you tried turning it off and on again? Does the issue affect all devices or just one?',
    s4_tip: 'Listen carefully to the answer. Record all details in the system.',
    s4_resolve_h: '✅ RESOLUTION STEPS',
    s4_resolve: 'Okay [Client Name], based on your description, I will escalate this issue to our technical team. They will contact you within 24 hours.',
    s4_escalate_h: '🔁 ESCALATION',
    s4_escalate: 'We are very sorry [Client Name]. This issue requires additional support. I will forward it to our specialized team and they will call you as soon as possible.',
    s5: 'Section 5: Satisfaction Calls',
    s5_goal: 'Call each client monthly to assess their satisfaction with our services, record any issues, and schedule in-person visits when needed.',
    s5_1: '5.1 OPENING THE CONVERSATION', s5_1_h: '📞 SATISFACTION CALL — INTRODUCTION',
    s5_1_intro: (n: string) => `Hello [Client Name]! My name is ${n} from Moinfotech. I'm calling for our monthly customer satisfaction check-in. Do you have a few minutes to talk about our services?`,
    s5_1_if: '[If client has time]',
    s5_1_cont: 'Thank you! We want to know how you feel about our services and if there is anything we can improve.',
    s5_2: '5.2 ASKING ABOUT SERVICES (RATING)', s5_2_h: '⭐ SATISFACTION RATING (1-5)',
    s5_2_ask: 'On a scale of 1 to 5, where 1 is very poor and 5 is excellent, how would you rate our services?',
    s5_2_r1: '⭐ 1 = Very Poor', s5_2_r2: '⭐⭐ 2 = Poor', s5_2_r3: '⭐⭐⭐ 3 = Average',
    s5_2_r4: '⭐⭐⭐⭐ 4 = Good', s5_2_r5: '⭐⭐⭐⭐⭐ 5 = Excellent',
    s5_2_why: 'Thank you! Is there a specific reason for that rating?',
    s5_2_tip: 'Record the rating in the system immediately. If the client hesitates, help them by giving examples.',
    s5_3: '5.3 RECORDING OUTCOMES',
    s5_3_sat_h: '😊 CLIENT IS SATISFIED (Satisfied)', s5_3_sat: 'We are so happy to hear that! Your positive feedback motivates us to continue providing excellent service. Do you have any suggestions for improvement?',
    s5_3_sat_note: '[Record: outcome = satisfied, rating, and any feedback]',
    s5_3_imp_h: '🔧 NEEDS IMPROVEMENT (Needs Improvement)', s5_3_imp: 'Thank you for your honesty. Your suggestion is very important to us. I will record it and our team will work on it.',
    s5_3_imp_note: '[Record: outcome = needs_improvement, rating, and full details]',
    s5_3_comp_h: '😟 COMPLAINT (Complaint)', s5_3_comp: 'We are very sorry for the inconvenience. I understand how frustrating that is. I will record your complaint and our team will get back to you as soon as possible.',
    s5_3_comp_note: '[Record: outcome = complaint — suggest a visit if the issue is serious]',
    s5_3_sug_h: '💡 IDEA/SUGGESTION (Suggestion)', s5_3_sug: 'Thank you for that idea! We love receiving feedback from our clients. I will record it and forward it to the relevant team.',
    s5_3_sug_note: '[Record: outcome = suggestion, and suggestion details]',
    s5_4: '5.4 SCHEDULING AN IN-PERSON VISIT (APPOINTMENT)', s5_4_h: '📍 REQUESTING A CLIENT VISIT',
    s5_4_ask: 'Because of this issue, we would like to schedule an in-person visit so we can help you better. Is there a day and time that works for you?',
    s5_4_yes: '[If client agrees]', s5_4_confirm: 'Great, I have scheduled your visit for [Date]. Our representative will come to see you. Are there any other details about the visit?',
    s5_4_rec: '[Record in system: appointment_requested = Yes, date, and notes]',
    s5_4_no: '[If client declines]', s5_4_decline: 'No problem. If you change your mind, we are ready to help you anytime.',
    s5_4_tip: 'Suggest visits for serious complaints or technical issues that cannot be resolved over the phone.',
    s5_5: '5.5 CLIENT DOES NOT ANSWER', s5_5_h: '📵 NO ANSWER / UNREACHABLE',
    s5_5_steps: ['Try 2-3 times at different times', 'If still no answer, record in system: outcome = no_answer or unreachable'],
    s5_5_auto: 'automatic follow-up call', s5_5_s3: 'the next business day', s5_5_s4: 'The follow-up call will appear on your schedule',
    s5_6: '5.6 CLOSING THE CONVERSATION', s5_6_h: '✅ END OF SATISFACTION CALL',
    s5_6_close: 'Thank you so much [Client Name] for your time and feedback. Your feedback helps us greatly improve our services. We will continue calling you monthly to check in.',
    s5_6_if: '[If there is a scheduled visit]', s5_6_appt: 'And remember, our team will come to visit you on [Date]. We will send you a reminder message.',
    s5_6_bye: 'Have a great day! For any help, do not hesitate to call us.',
    qr: 'Quick Reference Table', qr_sit: 'Situation', qr_say: 'What to say',
    qr_angry: 'Client is angry', qr_angry_say: 'I understand your frustration. This is important to us too.',
    qr_dunno: 'You don\'t know the answer', qr_dunno_say: 'Just a moment please. I want to give you the right answer.',
    qr_mgr: 'Client wants a manager', qr_mgr_say: 'I understand. Let me get my supervisor right away.',
    qr_sat: 'Client is satisfied (satisfaction call)', qr_sat_say: 'We are so happy to hear that! Your rating is very important to us.',
    qr_prob: 'Client has a problem (satisfaction call)', qr_prob_say: 'We are very sorry. I will record it and our team will work on it quickly.',
    qr_visit: 'Requesting a visit', qr_visit_say: 'We would like to schedule a visit so we can help you better.',
    qr_end: 'Closing the conversation', qr_end_say: 'Thank you for your time [Client Name]. Have a great day!',
    goal: 'Goal',
  },
};

interface CallScriptDrawerProps {
  opened: boolean;
  onClose: () => void;
  agentName: string;
  defaultSection?: string;
}

export default function CallScriptDrawer({ opened, onClose, agentName, defaultSection = 'section5' }: CallScriptDrawerProps) {
  const [lang, setLang] = useState<'sw' | 'en'>('sw');
  const t = script[lang];

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      title={
        <Group gap="sm">
          <IconScript size={20} />
          <Text fw={600}>Customer Care Call Script</Text>
          <Badge size="sm" variant="light" color="teal">{agentName}</Badge>
        </Group>
      }
      position="right"
      size="xl"
      padding="md"
    >
      <Stack gap="md">
        <Group justify="space-between">
          <Paper p="sm" radius="sm" bg="var(--mantine-color-blue-light)" style={{ flex: 1 }}>
            <Text size="sm" fw={500}>💡 {t.tip}</Text>
          </Paper>
          <SegmentedControl
            value={lang}
            onChange={(v) => setLang(v as 'sw' | 'en')}
            data={[
              { value: 'sw', label: '🇹🇿 Swahili' },
              { value: 'en', label: '🇬🇧 English' },
            ]}
            size="sm"
          />
        </Group>

        <Accordion variant="separated" multiple defaultValue={[defaultSection]}>
          {/* Section 1: New Contact */}
          <Accordion.Item value="section1">
            <Accordion.Control icon={<IconPhone size={18} />}>{t.s1}</Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s1_answer_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s1_answer(agentName)}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s1_call_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s1_call(agentName)}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s1_services_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s1_services}</Text></Text>
                  <List size="sm" mt="xs" spacing={2}>
                    <List.Item><Text span fw={700}>Web Hosting &amp; Domain</Text> — {t.s1_svc_hosting}</List.Item>
                    <List.Item><Text span fw={700}>Website Design</Text> — {t.s1_svc_web}</List.Item>
                    <List.Item><Text span fw={700}>Custom Systems</Text> — {t.s1_svc_systems}</List.Item>
                    <List.Item><Text span fw={700}>Bulk SMS</Text> — {t.s1_svc_sms}</List.Item>
                    <List.Item><Text span fw={700}>Mobile Apps</Text> — {t.s1_svc_apps}</List.Item>
                    <List.Item><Text span fw={700}>24/7 Support</Text> — {t.s1_svc_support}</List.Item>
                  </List>
                  <Text size="xs" c="dimmed" mt="xs">📍 Njuweni Hotel, 1st Floor, Room 134, Mail Moja, Kibaha | 📞 +255 689 011 111</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s1_close_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s1_close}</Text></Text>
                </Paper>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* Section 2: Follow-up */}
          <Accordion.Item value="section2">
            <Accordion.Control icon={<IconRepeat size={18} />}>{t.s2}</Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s2_follow_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s2_follow(agentName)}</Text></Text>
                </Paper>
                <Paper p="xs" radius="sm" bg="var(--mantine-color-yellow-light)">
                  <Text size="xs">💡 {t.s2_tip}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="green" mb={4}>{t.s2_happy_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s2_happy}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="red" mb={4}>{t.s2_issue_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s2_issue}</Text></Text>
                </Paper>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* Section 3: Payment Collection */}
          <Accordion.Item value="section3">
            <Accordion.Control icon={<IconFileInvoice size={18} />}>{t.s3}</Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s3_remind_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s3_remind(agentName)}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="orange" mb={4}>{t.s3_late_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s3_late(agentName)}</Text></Text>
                </Paper>
                <Paper p="xs" radius="sm" bg="var(--mantine-color-yellow-light)">
                  <Text size="xs">💡 {t.s3_tip}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="red" mb={4}>{t.s3_overdue_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s3_overdue(agentName)}</Text></Text>
                </Paper>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* Section 4: Technical Support */}
          <Accordion.Item value="section4">
            <Accordion.Control icon={<IconAlertTriangle size={18} />}>{t.s4}</Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s4_receive_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s4_receive(agentName)}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s4_diag_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s4_diag}</Text></Text>
                </Paper>
                <Paper p="xs" radius="sm" bg="var(--mantine-color-yellow-light)">
                  <Text size="xs">💡 {t.s4_tip}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="green" mb={4}>{t.s4_resolve_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s4_resolve}</Text></Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="red" mb={4}>{t.s4_escalate_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s4_escalate}</Text></Text>
                </Paper>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* Section 5: Satisfaction Calls */}
          <Accordion.Item value="section5">
            <Accordion.Control icon={<IconHeartHandshake size={18} />}>
              <Text fw={700}>{t.s5}</Text>
            </Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <Paper p="xs" radius="sm" bg="var(--mantine-color-teal-light)">
                  <Text size="xs" fw={500}><Text span fw={700}>{t.goal}:</Text> {t.s5_goal}</Text>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_1}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_1_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_1_intro(agentName)}</Text></Text>
                  <Text size="sm" mt="xs" c="dimmed">{t.s5_1_if}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_1_cont}</Text></Text>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_2}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_2_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_2_ask}</Text></Text>
                  <List size="sm" mt="xs" spacing={2}>
                    <List.Item>{t.s5_2_r1}</List.Item>
                    <List.Item>{t.s5_2_r2}</List.Item>
                    <List.Item>{t.s5_2_r3}</List.Item>
                    <List.Item>{t.s5_2_r4}</List.Item>
                    <List.Item>{t.s5_2_r5}</List.Item>
                  </List>
                  <Text size="sm" mt="xs"><Text span fw={700}>{t.s5_2_why}</Text></Text>
                </Paper>
                <Paper p="xs" radius="sm" bg="var(--mantine-color-yellow-light)">
                  <Text size="xs">💡 {t.s5_2_tip}</Text>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_3}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="green" mb={4}>{t.s5_3_sat_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_3_sat}</Text></Text>
                  <Text size="xs" c="dimmed" mt={4}>{t.s5_3_sat_note}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="orange" mb={4}>{t.s5_3_imp_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_3_imp}</Text></Text>
                  <Text size="xs" c="dimmed" mt={4}>{t.s5_3_imp_note}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="red" mb={4}>{t.s5_3_comp_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_3_comp}</Text></Text>
                  <Text size="xs" c="dimmed" mt={4}>{t.s5_3_comp_note}</Text>
                </Paper>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_3_sug_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_3_sug}</Text></Text>
                  <Text size="xs" c="dimmed" mt={4}>{t.s5_3_sug_note}</Text>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_4}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_4_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_4_ask}</Text></Text>
                  <Text size="sm" mt="xs" c="dimmed">{t.s5_4_yes}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_4_confirm}</Text></Text>
                  <Text size="xs" c="dimmed" mt={4}>{t.s5_4_rec}</Text>
                  <Text size="sm" mt="xs" c="dimmed">{t.s5_4_no}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_4_decline}</Text></Text>
                </Paper>
                <Paper p="xs" radius="sm" bg="var(--mantine-color-yellow-light)">
                  <Text size="xs">💡 {t.s5_4_tip}</Text>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_5}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_5_h}</Text>
                  <List size="sm" type="ordered" spacing={4}>
                    <List.Item>{t.s5_5_steps[0]}</List.Item>
                    <List.Item>{t.s5_5_steps[1]}</List.Item>
                    <List.Item>System schedules <Text span fw={700}>{t.s5_5_auto}</Text> {t.s5_5_s3}</List.Item>
                    <List.Item>{t.s5_5_s4}</List.Item>
                  </List>
                </Paper>
                <Text size="sm" fw={700} c="teal">{t.s5_6}</Text>
                <Paper p="sm" radius="sm" withBorder>
                  <Text size="xs" fw={700} c="blue" mb={4}>{t.s5_6_h}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_6_close}</Text></Text>
                  <Text size="sm" mt="xs" c="dimmed">{t.s5_6_if}</Text>
                  <Text size="sm"><Text span fw={700}>{t.s5_6_appt}</Text></Text>
                  <Text size="sm" mt="xs"><Text span fw={700}>{t.s5_6_bye}</Text></Text>
                </Paper>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* Quick Reference */}
          <Accordion.Item value="quickref">
            <Accordion.Control icon={<IconStar size={18} />}>{t.qr}</Accordion.Control>
            <Accordion.Panel>
              <Table striped highlightOnHover withTableBorder>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>{t.qr_sit}</Table.Th>
                    <Table.Th>{t.qr_say}</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_angry}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_angry_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_dunno}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_dunno_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_mgr}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_mgr_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_sat}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_sat_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_prob}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_prob_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_visit}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_visit_say}&quot;</Text></Table.Td></Table.Tr>
                  <Table.Tr><Table.Td><Text size="xs">{t.qr_end}</Text></Table.Td><Table.Td><Text size="xs" fs="italic">&quot;{t.qr_end_say}&quot;</Text></Table.Td></Table.Tr>
                </Table.Tbody>
              </Table>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
      </Stack>
    </Drawer>
  );
}
