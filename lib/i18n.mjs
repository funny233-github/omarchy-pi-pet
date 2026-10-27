// 界面语言：中文 / 英文。language 设置为 auto 时从系统 locale 判断。
// 动画素材、表情包图片本身带中文，无法翻译；这里只翻译显示文字，动画在菜单里显示英文名，文件名不变。

/** 设置值（auto / zh / en）+ 环境变量 → 'zh' | 'en'。auto 按 GNU 惯例：LANGUAGE > LC_ALL > LC_MESSAGES > LANG */
export function resolveLang(setting, env) {
  if (setting === 'zh' || setting === 'en') return setting;
  const e = env || {};
  const locale = (e.LANGUAGE || '').split(':')[0] || e.LC_ALL || e.LC_MESSAGES || e.LANG || '';
  return /^zh/i.test(locale) ? 'zh' : 'en';
}

const STRINGS = {
  zh: {
    configError: '配置文件写错啦：{error}',
    notifyWaiting: '需要你确认',
    notifySuccess: '任务完成',
    notifyError: '出错了',
    menuMurmur: '碎碎念',
    menuMurmurBusy: '碎碎念（正在想…）',
    menuNoModel: '碎碎念（先设置模型）',
    menuChat: '对话',
    menuChatNoModel: '对话（先设置模型）',
    chatPlaceholder: '和她说点什么，回车发送',
    chatNoModel: '先在 config.jsonc 里填 murmur.model 才能说话',
    chatBusy: '还在想上一句……',
    chatPrompt: '主人对你说：{text}',
    chatStyle: '用两三句口语回答，不要 Markdown，不要列表。',
    menuContext: '看看上下文',
    menuHome: '回到初始位置',
    menuReload: '重载配置',
    menuHide: '隐藏',
    toolSuffix: '（{tool}）',
    ctxUsage: '上下文 {pct}%',
    ctxUnknown: '我还没说过话呢，脑袋空空~',
    ctxIdle: '现在没在干活呢~',
    errTimeout: '想了太久，没说出来……',
    errKilled: '',
    errPi: 'pi 报错啦：{detail}',
    errExit: 'pi 退出了（{detail}）',
    errSilent: '想了一会儿，什么也没说……',
    errNoModel: '先给我设个模型吧，不然说不了话呢',
    busy: '还在想上一句呢……',
    // ---- 提示词（人设本身在 assets/persona.*.md，这里只加任务）
    murmurNow: '现在是 {time}。随口碎碎念一句。',
    murmurMeme: '这次配的表情包画面是：{desc}，让这句话和画面呼应。',
    murmurOutput: '只输出这一句话本身，不要引号，不要换行。',
  },
  en: {
    configError: 'Config file has an error: {error}',
    notifyWaiting: 'Needs your approval',
    notifySuccess: 'Task complete',
    notifyError: 'Something went wrong',
    menuMurmur: 'Murmur',
    menuMurmurBusy: 'Murmur (thinking…)',
    menuNoModel: 'Murmur (set a model first)',
    menuChat: 'Chat',
    menuChatNoModel: 'Chat (set a model first)',
    chatPlaceholder: 'Say something, Enter to send',
    chatNoModel: 'Set murmur.model in config.jsonc first',
    chatBusy: 'Still thinking about the last one…',
    chatPrompt: 'Your owner says: {text}',
    chatStyle: 'Answer in two or three spoken sentences, no Markdown, no lists.',
    menuContext: 'Show context usage',
    menuHome: 'Back to start position',
    menuReload: 'Reload config',
    menuHide: 'Hide',
    toolSuffix: ' ({tool})',
    ctxUsage: 'Context {pct}%',
    ctxUnknown: "I haven't spoken yet, my head is empty~",
    ctxIdle: 'Nothing running right now~',
    errTimeout: 'Thought about it too long…',
    errKilled: '',
    errPi: 'pi reported an error: {detail}',
    errExit: 'pi exited ({detail})',
    errSilent: 'Thought for a while, said nothing…',
    errNoModel: 'Set a model for me first, or I cannot speak',
    busy: 'Still thinking about the last one…',
    // ---- prompts (the persona lives in assets/persona.*.md; this is the task)
    murmurNow: 'It is {time} now. Murmur one casual line to yourself.',
    murmurMeme: 'The sticker shown with it depicts: {desc}. Make the line match the picture.',
    murmurOutput: 'Output only that one line in English, no quotes, no line breaks.',
  },
};

/** 取一条文字并替换 {name} 占位；缺失时回退到中文，再回退到 key 本身 */
export function t(lang, key, params) {
  const table = STRINGS[lang] || STRINGS.zh;
  let s = key in table ? table[key] : STRINGS.zh[key] ?? key;
  if (params) for (const k of Object.keys(params)) s = s.split('{' + k + '}').join(String(params[k]));
  return s;
}

// ---- 英文版默认文案：只在用户没有自定义 workStatusTexts / whisperPrompt 时替换内置中文

/** 档位顺序同 workStatusTexts：thinking / working / result / waiting / success / error */
export const WORK_STATUS_TEXTS_EN = [
  ['Thinking about the next step', 'Let me sort out my thoughts~', 'Planning what to do next'],
  ['Working on it', 'This step is in progress', "Still busy, don't disturb me~"],
  ["That step's done, on to the next", "One step down, let's keep going~"],
  ['Need you to confirm something', 'Please take a look here', "Your turn to decide, I'll wait~"],
  ['All done this round, great job!', 'Task complete, time to slack off~'],
  ["That step didn't quite work", 'Ran into a little problem', 'Got stuck here, waiting for you'],
];

export const WHISPER_PROMPT_EN =
  "You are a chibi blue-haired maid living on your owner's desktop who murmurs to herself now and then. "
  + 'Keep it natural and casual: one short line (under 15 words), gentle and a little playful. '
  + "Plain language, don't explain yourself, don't mention being an AI.";

// ---- 菜单：分组 / 分类名与动画显示名（英文）

const GROUP_LABELS_EN = {
  动作: 'Actions',
  待机: 'Idle',
  转向: 'Turn',
  拖拽: 'Drag',
  点击回应: 'Click reactions',
  移动: 'Move',
  '余额档位': 'Usage levels',
  context: 'Context levels',
  碎碎念: 'Murmurs',
  工作状态: 'Work status',
  小动作: 'Small actions',
  玩耍: 'Play',
  吃什么: 'Food',
  时节: 'Seasons & festivals',
  文字: 'Text',
};

export const ANIM_LABELS_EN = {
  待机呼吸休闲: 'Idle breathing',
  东张西望: 'Looking around',
  被鼠标拖拽悬空反馈: 'Dangling while dragged',
  '点击回应-开心跃动': 'Happy hop',
  '点击回应-害羞惊讶': 'Shy surprise',
  '点击回应-傲娇生气': 'Tsundere pout',
  '点击回应-挠痒咯咯笑': 'Ticklish giggle',
  '点击回应-元气挥手': 'Cheerful wave',
  螃蟹走路: 'Crab walk',
  原地漂浮踏步: 'Floating march',
  原地左转奔跑: 'Turn and run',
  悠闲哼歌: 'Humming leisurely',
  超大伸懒腰: 'Big stretch',
  原地敲击桌面互动: 'Tapping on the desk',
  原地重力下蹲压缩: 'Squat squish',
  哈欠连天: 'Yawning nonstop',
  原地小憩沉眠: 'Quick nap',
  女仆屈膝礼仪: 'Maid curtsy',
  被吓一跳: 'Startled',
  小幅度原地360度旋转展示: 'Little 360° twirl',
  偷吃零食被抓住: 'Caught sneaking snacks',
  用鲸鱼尾巴拍打地面: 'Tail slap',
  打瞌睡被惊醒: 'Dozing off, jolted awake',
  照镜子: 'Looking in the mirror',
  整体换装试色: 'Outfit color swap',
  轻快记录: 'Taking quick notes',
  写代码: 'Writing code',
  摇扇纳凉: 'Fanning to cool off',
  晨间刷牙: 'Morning tooth brushing',
  原地专心玩魔方: "Solving a Rubik's cube",
  原地蹲下玩玩具汽车: 'Playing with a toy car',
  鲸鱼吐泡泡特效: 'Whale bubbles',
  原地跳跃抓碎头顶物品: 'Jumping to grab overhead',
  玩游戏气急败坏: 'Rage gaming',
  玩水枪: 'Water gun',
  小提琴演奏: 'Violin performance',
  蓝鲸现世: 'Blue whale appears',
  优雅女仆舞: 'Elegant maid dance',
  轻快摇摆舞: 'Bouncy sway dance',
  可爱宅舞: 'Cute otaku dance',
  吹气球: 'Blowing balloons',
  动物环绕: 'Surrounded by animals',
  放风筝: 'Flying a kite',
  拆礼物: 'Opening a present',
  变鸽子: 'Pulling out a dove',
  扑克魔术: 'Card trick',
  抽陀螺: 'Whipping a spinning top',
  吹笛子: 'Playing the flute',
  蝴蝶蜜蜂环绕头顶开花: 'Flowers, bees and butterflies',
  撸猫: 'Petting a cat',
  凭空生花: 'Conjuring flowers',
  骑木马: 'Riding a rocking horse',
  三球抛接: 'Three-ball juggling',
  踢毽子: 'Shuttlecock kicking',
  下五子棋: 'Playing gomoku',
  荡秋千: 'On a swing',
  吃白饭: 'Eating plain rice',
  大口吃零食: 'Munching snacks',
  吃Token: 'Eating tokens',
  吃早餐: 'Breakfast',
  吃午餐: 'Lunch',
  吃晚餐: 'Dinner',
  吃冰淇淋融化: 'Melting ice cream',
  吃大闸蟹: 'Hairy crab',
  吃糖葫芦: 'Candied haws',
  吃长寿面: 'Longevity noodles',
  吃西瓜: 'Watermelon',
  涮火锅: 'Hot pot',
  被落叶淹没: 'Buried in autumn leaves',
  中秋赏月吃月饼: 'Mooncakes under the full moon',
  堆雪人: 'Building a snowman',
  放烟花: 'Fireworks',
  吃粽子: 'Zongzi (rice dumplings)',
  吃年糕: 'New Year rice cake',
  吃青团: 'Qingtuan (green rice balls)',
  吃腊八粥: 'Laba porridge',
  吃重阳糕: 'Double Ninth cake',
  收红包: 'Receiving a red envelope',
  写福字: 'Writing "Fu" for luck',
  穿针乞巧: 'Qixi needle threading',
  舞狮头: 'Lion dance',
  讨糖南瓜灯: "Trick-or-treat jack-o'-lantern",
  插茱萸赏菊: 'Dogwood and chrysanthemums',
  放河灯: 'Floating river lanterns',
  萌化小幽灵: 'Cute little ghost',
  装点圣诞树: 'Decorating the Christmas tree',
  放孔明灯: 'Sky lanterns',
  吃汤圆: 'Tangyuan (sweet rice balls)',
  吃饺子: 'Dumplings',
  '是啊，吃什么': '"Yeah, what to eat?"',
  深度思考碎碎念: 'Deep-thinking murmur',
  '余额-钱袋满溢': 'Overflowing purse',
  '余额-金袋叮当': 'Jingling gold bag',
  '余额-钱袋如常': 'Purse as usual',
  '余额-数金皱眉': 'Frowning at coins',
  '余额-袋空如洗': 'Empty purse',
  '余额-分文不剩': 'Not a coin left',
  '碎碎念-擦桌碎碎念': 'Wiping the desk',
  '碎碎念-发呆碎碎念': 'Spacing out',
  '碎碎念-对屏碎碎念': 'Talking to the screen',
  '工作状态-思考冒泡': 'Thinking bubbles',
  '工作状态-忙碌点按': 'Busy tapping',
  '工作状态-清点归档': 'Sorting and filing',
  '工作状态-原地踱步张望': 'Pacing and watching',
  '工作状态-雀跃庆祝': 'Joyful celebration',
  '工作状态-垂头叹气冒汗': 'Sighing and sweating',
};

/** 菜单分组名：config 里的 events 键（balance 已被 context 取代）→ 显示名 */
const GROUP_LABELS_ZH = { context: '上下文档位' };

/**
 * 把 dsh-pet 的菜单树翻成当前语言的显示名（leaf.anim 保持原名用于播放）。
 * zh：只补分组的显示名（动画名本身是中文）；en：分组和动画都翻。
 */
export function translateMenuTree(tree, lang) {
  const walk = (nodes) =>
    nodes.map((n) => {
      const groupLabel = lang === 'en' ? GROUP_LABELS_EN[n.label] || n.label : GROUP_LABELS_ZH[n.label] || n.label;
      if (n.children) return Object.assign({}, n, { label: groupLabel, children: walk(n.children) });
      return Object.assign({}, n, { label: lang === 'en' ? (n.anim && ANIM_LABELS_EN[n.anim]) || n.label : n.label });
    });
  return walk(tree);
}
