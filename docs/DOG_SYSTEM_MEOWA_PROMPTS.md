# 小狗系统 Meowa 素材生成清单

目标是做一只雪白色线条小狗，作为女孩桌宠可以收养的小宠物。角色使用纯白毛色、冰蓝阴影、圆润深灰描边和淡蓝色项圈；UI 使用淡蓝、白色和少量银灰，不与女孩的粉色主 UI 混在一起。

## 先做角色定稿

先只生成一张身份参考图。使用 Meowa 的“64 像素精致小狗”档位和 `1:1` 画布；有透明背景选项时开启。角色满意后，把这一张作为后续所有方向和动作的唯一参考图，不要在中途换参考。

**身份参考图提示词：**

> A tiny full-body puppy for a refined 64-pixel game sprite, shown in a relaxed three-quarter view facing right. All of its fur is solid snow white across the head, ears, muzzle, body, legs, and tail, with only very pale ice-blue shading. It has a compact rounded body, short legs, floppy ears, a small fluffy tail, warm expressive eyes, charcoal eyes and nose, clean dark-charcoal pixel outlines, and one pale-blue collar with a tiny silver tag. Keep the design simple and readable at 64 pixels, centered with clear transparent padding. The fur must not contain brown, tan, beige, cream, orange, gray, or colored patches. No scenery, ground shadow, text, clothing, or other characters.

如果已经生成的小狗造型满意、只是颜色错误，不要重新抽造型；把棕色结果放进图片编辑并使用：

> Keep the exact puppy pose, silhouette, proportions, facial features, pixel clusters, and transparent background. Recolor all fur on the head, ears, muzzle, body, legs, and tail to solid snow white, using only very pale ice-blue pixels for shading. Keep the eyes, nose, and outer pixel outline dark charcoal, and keep the collar pale blue with a silver tag. Remove every brown, tan, beige, cream, orange, gray, and colored fur patch. Do not change the pose or add details.

验收时只看四件事：轮廓是否干净、四条腿是否清楚、项圈是否只有一个、缩小到桌面尺寸后表情是否还能看懂。任何一项不对，都只重做这张参考图，不要先花额度做动画。

## 五方向定稿

身份参考通过后，用它作为唯一参考图进入角色多视图工具。选择 Pixel、Mirror 五方向，并把最终单格输出尺寸设为 `64x64`；不要用新的文字生图重新猜一次身份。

> Using the exact same puppy identity and proportions as the reference, create a clean five-view turnaround sheet for 2D game animation: front, back, right side, front-right three-quarter view, and back-right three-quarter view. Keep the white body, rounded charcoal outline, floppy ears, fluffy tail, pale-blue collar, and silver tag identical in every view. Place the five full-body views separately with equal scale and clear spacing on a transparent background. Neutral standing pose only. No labels, scenery, shadows, props, or additional poses.

实际只需生成这五个方向，运行时镜像得到左、左上和左下，可以省掉三套重复动画额度。

## 第一批动画

每个动画都使用已定稿的小狗参考图。小狗本体保持原来的 64 像素比例；动画工具可以扩展透明运动画布，但不能把小狗重新放大成 128 或 256 像素角色。脚底锚点保持一致，不要让耳朵、尾巴或动作碰到画布边缘。

每次只生成一个动作；提示词里的方向可替换为 `front`、`back`、`right side`、`front-right` 或 `back-right`。

**待机循环，6–8 帧：**

> Animate this exact 64-pixel puppy in a seamless idle loop, facing right. It breathes gently, blinks once, and gives one small relaxed tail wag. Keep all paws planted and preserve the same snow-white fur, pale ice-blue shading, body proportions, outline, collar, sprite scale, and ground anchor. Use a transparent sprite-animation canvas with enough motion space, without enlarging the puppy.

**走路循环，8 帧：**

> Animate this exact 64-pixel puppy walking happily to the right in a seamless loop, with the legs clearly stepping one forward and one back. Use a readable four-leg walk cycle with a light head bob, softly bouncing floppy ears, and a gentle tail wag. Preserve its snow-white fur, identity, sprite scale, outline, pale-blue collar, and constant ground anchor. Use a transparent animation canvas without enlarging the puppy.

**坐下过渡，8 帧：**

> Animate this exact 64-pixel puppy naturally lowering from standing into a seated pose while facing right. The hind legs fold under the body, the front paws remain clear, and the ears settle with a small soft bounce. End in a stable seated pose. Preserve the snow-white fur, identity, sprite scale, outline, collar, and ground anchor on a transparent animation canvas.

**坐姿待机，6 帧循环：**

> Animate this exact seated 64-pixel puppy in a subtle seamless loop. It blinks, tilts its head slightly with curiosity, and gives one small tail wag while staying seated. Preserve the snow-white fur, identity, sprite scale, outline, collar, and ground anchor on a transparent animation canvas.

**睡觉过渡与睡眠待机：**

> Animate this exact 64-pixel puppy curling down from standing into a comfortable sleeping pose, facing right. It circles once very briefly, folds its paws, rests its head, and ends completely still in a compact pose. Preserve the snow-white fur, identity, sprite scale, outline, collar, and ground anchor on a transparent animation canvas.

> Animate this exact curled-up 64-pixel sleeping puppy in a very subtle seamless loop. Only the body breathes gently and one ear twitches once. Do not change its snow-white fur, position, silhouette, sprite scale, collar, or ground anchor. Use a transparent animation canvas.

**吃饭与喝水，分别 8 帧循环：**

> Animate this exact 64-pixel puppy eating happily from a small pale-blue food bowl in a seamless loop. Use gentle head dips and a tiny satisfied tail wag. Keep the bowl fixed on the ground and preserve the snow-white fur, puppy identity, sprite scale, outline, collar, and anchor. Use a transparent animation canvas.

> Animate this exact 64-pixel puppy drinking from a small pale-blue water bowl in a seamless loop. Use small rhythmic head and tongue movements with one soft ear bounce. Keep the bowl fixed and preserve the snow-white fur, identity, sprite scale, outline, collar, and anchor. Use a transparent animation canvas.

**开心、叼玩具和闯祸被发现：**

> Animate this exact 64-pixel puppy becoming excited and wagging its whole rear body while keeping the front paws near the same place. Add one tiny happy hop, then return to the starting pose for a seamless loop. Preserve its snow-white fur and sprite scale on a transparent animation canvas.

> Animate this exact 64-pixel puppy proudly carrying a small pale-blue ball in its mouth while walking to the right in a seamless loop. The ball remains securely held and does not cover the eyes. Preserve the snow-white fur, identity, sprite scale, outline, collar, and ground anchor on a transparent animation canvas.

> Animate this exact 64-pixel puppy after being caught making mischief. It freezes, lowers its ears, glances upward with a guilty expression, and sits down slowly with one small nervous tail movement. End in a stable apologetic pose. Preserve the snow-white fur, identity, sprite scale, and ground anchor on a transparent animation canvas.

## 狗和女孩的互动动画标注

实现时采用混合方案：小狗平时使用独立透明窗口；互动开始时把它移动到女孩窗口旁边并同步两个状态机。只有出现手臂遮挡小狗身体的近距离动作，才切换到一段女孩和小狗同帧的临时互动动画。

### `[仅小狗]` 不需要重新生成人物

- 跑向女孩、跟随女孩、绕女孩一圈、坐在脚边、抬头看她。
- 在女孩旁边摇尾巴、趴下、一起睡觉、叫醒女孩。
- 追球、叼球回来、叼拖鞋、拖动桌面小物件、闯祸后心虚。
- 蹭腿可以先用小狗自己的侧身贴近动画完成，女孩继续播放普通待机。

这些动作由 Godot 调整两个窗口的位置和播放时机，不需要把人画进小狗动画。

### `[需要女孩同步动作，建议分层生成]`

下面每组需要新增女孩动画，但女孩与小狗仍分别导出透明帧，在 Godot 中按固定锚点同步，复用性最高：

- `girl_pet_dog` + `dog_being_petted`：女孩蹲下摸头，小狗坐着眯眼摇尾巴。
- `girl_offer_treat` + `dog_take_treat`：女孩伸手递零食，小狗向上轻轻叼走。
- `girl_throw_ball` + `dog_fetch_start`：女孩把球抛出，小狗做起跑动作，后续追球只用小狗移动逻辑。
- `girl_scold_dog` + `dog_guilty`：女孩叉腰或轻轻指向小狗，小狗低耳坐下认错。
- `girl_ask_paw` + `dog_give_paw`：女孩伸出手掌，小狗抬起前爪。

生成这类动作时，人物动画应只对一个固定的空位置做动作，不要让模型临时生成另一只狗；小狗动画也不要生成人手。接入时统一右侧互动锚点，左侧直接镜像。

### `[女孩和小狗必须一起做，建议同帧生成]`

- `girl_lift_dog`：女孩弯腰把小狗抱离地面。
- `girl_hug_dog`：小狗位于女孩怀里，手臂需要正确遮住身体。
- `girl_carry_dog_idle`：女孩抱着小狗站立，小狗在怀中轻微摇尾或动耳朵。
- `girl_tug_of_war_dog`：双方同时咬住/握住同一根绳结玩具，接触位置必须连续。

这些动作存在明显肢体接触和前后遮挡，分别生成后很容易出现手穿过小狗、距离漂移或绳子断开。最稳妥的流程是先用女孩参考图和定稿小狗拼出一张静态接触关键帧，再把关键帧送入 Meowa 做动画；不要直接靠纯文字让模型同时重新设计两名角色。

第一版不必生成任何人物互动动画。先用 `[仅小狗]` 的靠近、坐下、摇尾、睡在旁边和心虚动作完成可玩的陪伴原型；第二版再优先补 `摸头`、`训话` 和 `握手` 三组分层动画，最后才制作成本较高的抱起与拥抱同帧动画。

## 淡蓝 UI 合集

建议一次生成一张 `4:3`、2K、Detailed 的 UI sheet，背景移除选 Standard。先不要生成任何文字，文字由 Godot 原生绘制，避免乱码和无法复用。

> Create one cohesive UI asset sheet for a cute white puppy companion system in a desktop game. Use pale powder blue, clean white, soft silver-gray, and tiny pink accent details. Include a wide puppy status panel, a compact adoption panel, a small shop panel, an inventory tray, an affinity progress frame, food and water meters, a name plate, a draggable title bar, close and back icon buttons, confirm and cancel buttons, plus compact tab buttons for home, care, play, shop, and memories. Add subtle lace edging, tiny paw-print details, bows, and rounded floral corners while keeping the UI suitable for a human girl's desktop pet rather than a veterinary app. Keep every component separate with clear spacing. No text, no animals, no mock screen, no background scene.

## 家具、物品与反馈特效合集

这张也建议 `4:3`、2K、Detailed、Standard 背景移除。物件要正面或轻微三分之四视角，统一光线和大小关系。

> Create a separated game-asset sheet for a tiny white line-art puppy living on a desktop. Include a pale-blue and white fabric dog bed, a small elegant doghouse, empty food and water bowls, bowls filled with food and water, a pale-blue ball, rope toy, soft slipper, small blanket, grooming brush, leash, gift box, and a tiny storage basket. Also include separate feedback effects: blue paw prints, small hearts, sparkle stars, a question mark, an exclamation mark, a sweat drop, a soft dust puff, and a gentle impact burst. The props should feel cute and refined enough to belong beside a teenage girl character. Keep every item separate, fully visible, consistently lit, and easy to cut out. No text, no characters, no scenery, and no overlapping items.

## 交付给项目时

请保留 Meowa 原始 ZIP，并把导出的文件按下面命名，方便直接接入：

- `dog_reference.png`
- `dog_turnaround.png`
- `dog_idle.zip`
- `dog_walk_right.zip`、`dog_walk_front_right.zip`、`dog_walk_back_right.zip`、`dog_walk_front.zip`、`dog_walk_back.zip`
- `dog_sit.zip`、`dog_sit_idle.zip`、`dog_sleep_down.zip`、`dog_sleep_idle.zip`
- `dog_eat.zip`、`dog_drink.zip`、`dog_happy.zip`、`dog_carry_ball.zip`、`dog_guilty.zip`
- `dog_ui_sheet.zip`
- `dog_props_effects.zip`

第一轮最省额度的做法是：身份参考图通过后，只生成 `idle`、`walk_right`、`sit`、`sleep_down`、`sleep_idle` 和两张 UI/道具合集。它们足够先完成收养、跟随、睡觉、狗窝和基础养成原型，其余动作等原型手感确认后再补。

## 巨龙彩蛋参考图

先只生成一张右向飞行定稿图，不做动画：

> A powerful and elegant full-body dragon for a 2D pixel-art desktop companion game, shown in a clear right-facing flying key pose. It has sleek obsidian-black scales, luminous cyan-blue markings, large readable wings, a long flowing tail, sharp silver horns, and a confident heroic silhouette. Keep the upper back and base of the neck clear and unobstructed so a small chibi girl can ride there later. Use crisp detailed pixel art that remains readable at desktop-pet size, with generous transparent space around the wings and tail. No rider, no saddle, no scenery, no text, no cropping, and no fire or effects covering the body.

建议用横向画布生成，先确认龙的体型、背部骑乘位置和女孩的比例，再决定是否制作起飞、巡航、转向和降落动画。
