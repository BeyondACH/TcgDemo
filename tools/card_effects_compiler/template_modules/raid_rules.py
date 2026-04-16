
def build_trigger_raid_rules(
    TemplateRule,
    *,
    regex_match,
    life_trigger_raid_choice_builder,
):
    return (
        TemplateRule(
            name="trigger.life_trigger.raid_choice",
            event_filter="ON_LIFE_TRIGGER",
            matcher=regex_match(r"このカードを手札に加えるか、必要エナジーを満たしている(?:場合|なら)、レイドさせる。"),
            builder=life_trigger_raid_choice_builder,
            priority=260,
            template_metadata={"family": "LIFE_TRIGGER_RAID_CHOICE", "variant": "add_to_hand_or_raid_if_possible"},
        ),
    )


def build_event_raid_rules(
    TemplateRule,
    *,
    exact_text_match,
    mcr_sheryl_raid_chain_override_builder,
):
    return (
        TemplateRule(
            name="event.mcr_sheryl_raid_chain_override",
            event_filter="ON_PLAY",
            matcher=exact_text_match("自分の山札の上から5枚見る。その中から〈シェリル・ノーム〉を2枚まで公開し手札に加える。残りを望む順で自分の山札の下に置く。その後、自分の場のレイド状態の〈シェリル・ノーム〉を1枚選び、レイド状態の上のカードを場外に置いてもよい。そうした場合、カードを1枚引き、自分の手札から必要エナジーを満たしこの効果で場外に置いたカードとカードナンバーが異なる〈シェリル・ノーム〉を1枚まで、選んだキャラのレイド元のカードにレイドさせる。"),
            builder=mcr_sheryl_raid_chain_override_builder,
            priority=220,
            template_metadata={"family": "SPECIAL_OVERRIDE", "variant": "mcr_sheryl_raid_chain_phase4"},
        ),
    )
