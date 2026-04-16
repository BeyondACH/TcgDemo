def build_trigger_preview_rules(
    TemplateRule,
    *,
    exact_text_match,
    regex_match,
    preview_top_then_choose_top_or_bottom_builder,
    preview_top_two_reorder_top_bottom_builder,
    preview_add_character_cards_builder,
    preview_add_to_hand_builder_factory,
    preview_add_to_hand_energy_threshold_builder,
    preview_add_to_hand_name_contains_builder,
):
    return (
        TemplateRule(
            name="trigger.preview_top.choose_top_or_bottom",
            event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
            matcher=exact_text_match("自分の山札の上から1枚見て、山札の上か下に置く。"),
            builder=preview_top_then_choose_top_or_bottom_builder,
            priority=210,
            template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "preview_one_then_choose_top_or_bottom"},
        ),
        TemplateRule(
            name="trigger.preview_top_two_reorder_top_bottom",
            event_filter=("ON_ENTER", "MAIN_ACTIVATE"),
            matcher=exact_text_match("自分の山札の上から2枚見て、山札の上と下に望む枚数ずつ望む順で置く。"),
            builder=preview_top_two_reorder_top_bottom_builder,
            priority=206,
            template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "preview_two_reorder_top_bottom_split"},
        ),
        TemplateRule(
            name="trigger.preview_add_character_cards",
            event_filter=("ON_ENTER", "MAIN_ACTIVATE", "ON_PLAY", "ON_ATTACK", "ON_BLOCK", "ON_LIFE_TRIGGER"),
            matcher=regex_match(r"・?自分の山札の上から(\d+)枚見る。その中からキャラカードを(\d+)枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
            builder=preview_add_character_cards_builder,
            priority=191,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_character_cards_then_reorder_bottom"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.007_or_trait_discard",
            event_filter="ON_ENTER",
            matcher=exact_text_match("自分の山札の上から3枚見る。その中から〈アルティメットまどか〉か［特徴：魔法少女］を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_builder_factory(
                count=3,
                filters=[
                    {
                        "type": "OR",
                        "filters": [
                            {"type": "NAME_IS", "value": "アルティメットまどか"},
                            {"type": "HAS_TRAIT", "value": "魔法少女"},
                        ],
                    }
                ],
                discard_after_add=True,
            ),
            priority=200,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.040_name_discard",
            event_filter="ON_ENTER",
            matcher=exact_text_match("自分の山札の上から5枚見る。その中から〈鹿目 まどか〉を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_builder_factory(
                count=5,
                requirements=[{"type": "CARD_NAME_IS", "value": "鹿目 まどか"}],
                discard_after_add=True,
            ),
            priority=200,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.043_name_or_trait_discard",
            event_filter="ON_ENTER",
            matcher=exact_text_match("自分の山札の上から3枚見る。その中から〈百江 なぎさ〉か［特徴：ピュエラ・マギ・ホーリー・クインテット］を1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_builder_factory(
                count=3,
                filters=[
                    {
                        "type": "OR",
                        "filters": [
                            {"type": "NAME_IS", "value": "百江 なぎさ"},
                            {"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"},
                        ],
                    }
                ],
                discard_after_add=True,
            ),
            priority=200,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.yellow_event_discard",
            event_filter="ON_ENTER",
            matcher=exact_text_match("自分の山札の上から4枚見る。その中から黄のイベントカードを1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_builder_factory(
                count=4,
                requirements=[
                    {"type": "CARD_TYPE_IS", "value": "EVENT"},
                    {"type": "CARD_COLOR_IS", "value": "YELLOW"},
                ],
                discard_after_add=True,
            ),
            priority=180,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.energy_threshold_discard",
            event_filter="ON_ENTER",
            matcher=regex_match(r"自分の山札の上から(\d+)枚見て、必要エナジーが(\d+)以下のキャラカードを1枚まで公開し手札に加える。残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_energy_threshold_builder,
            priority=190,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_discard_on_add"},
        ),
        TemplateRule(
            name="trigger.preview_add_to_hand.name_contains_discard",
            event_filter="ON_ENTER",
            matcher=regex_match(r"自分の山札の上から(\d+)枚見て、カード名に「(.+)」を含むキャラカードを1枚まで公開し手札に加える。残りを望む順で山札の下に置く。手札に加えた場合、自分の手札を1枚場外に置く。"),
            builder=preview_add_to_hand_name_contains_builder,
            priority=195,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_name_contains_discard_on_add"},
        ),
    )


def build_event_preview_rules(
    TemplateRule,
    *,
    regex_match,
    exact_text_match,
    conditional_preview_top_then_choose_builder,
    preview_add_character_cards_builder,
    preview_name_contains_dual_then_conditional_ready_ap_builder,
    preview_add_to_hand_builder_factory,
):
    return (
        TemplateRule(
            name="event.conditional_preview_top.choose_top_or_bottom",
            event_filter="ON_PLAY",
            matcher=regex_match(r"・?自分の場に〈(.+)〉がある場合、自分の山札の上から1枚見る。そのカードを自分の山札の上か下に置く。"),
            builder=conditional_preview_top_then_choose_builder,
            priority=211,
            template_metadata={"family": "PREVIEW_TOP_POSITION", "variant": "conditional_preview_one_then_choose_top_or_bottom"},
        ),
        TemplateRule(
            name="event.preview_add_character_cards",
            event_filter="ON_PLAY",
            matcher=regex_match(r"・?自分の山札の上から(\d+)枚見る。その中からキャラカードを(\d+)枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
            builder=preview_add_character_cards_builder,
            priority=200,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_character_cards_then_reorder_bottom"},
        ),
        TemplateRule(
            name="event.preview_name_contains_dual_then_conditional_ready_ap",
            event_filter="ON_PLAY",
            matcher=regex_match(r"自分の山札の上から(\d+)枚見る。その中からを持ちカード名に「(.+)」か「(.+)」を含むキャラカードを1枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。自分の場にカード名に「(.+)」を含むキャラとカード名に「(.+)」を含むキャラがある場合、自分のAPカードを1枚まで選び、アクティブにする。"),
            builder=preview_name_contains_dual_then_conditional_ready_ap_builder,
            priority=202,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_name_contains_dual_then_conditional_ready_ap"},
        ),
        TemplateRule(
            name="event.preview_add_to_hand.065_trait_distinct",
            event_filter="ON_PLAY",
            matcher=exact_text_match("自分の山札の上から5枚見る。その中から［特徴：ピュエラ・マギ・ホーリー・クインテット］を2枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。"),
            builder=preview_add_to_hand_builder_factory(
                count=5,
                filters=[{"type": "HAS_TRAIT", "value": "ピュエラ・マギ・ホーリー・クインテット"}],
                max_count=2,
                distinct_by="CARD_NAME",
                kind="TRIGGERED",
            ),
            priority=200,
            template_metadata={"family": "PREVIEW_ADD_TO_HAND", "variant": "preview_add_to_hand_distinct_names"},
        ),
    )
