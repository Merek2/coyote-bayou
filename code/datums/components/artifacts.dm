#define ART_MASTER var/obj/item/master = parent; if(!isitem(master)) CRASH("Artifact component has no master!!!")

#define ART_EQUIP "art_equip"
#define ART_UNEQUIP "art_unequip"
#define ART_TICK "art_tick"

#define ART_IDENT_MAX_DELTA 5 SECONDS
#define ART_IDENT_TIME 45 MINUTES

#define ART_PENANCE_TIME 20 MINUTES

/datum/component/artifact
	var/identified_preposition
	var/unidentified_prefix = "thingy"
	var/identified_prefix
	var/identified_suffix
	var/identified_name // if set, overrides the base item's name, mainly for rares and uniques
	var/rare_name
	var/rarity
	var/unique_tag
	var/value = 0
	var/unidentified_desc = "Looks kinda odd!"
	var/identified_desc = "It throbs with power."
	var/list/effects = list()
	var/list/effect_desc = list()
	var/list/identifying = list()
	var/list/identified_by = list()
	var/list/identify_jobs = list()
	var/process_flags = ART_PROCESS_NEEDS_MOB
	var/current_slot = null
	var/datum/weakref/current_location
	var/datum/weakref/affecting
	var/my_color = "#FFFFFF"
	var/beatitude = UNCURSED
	dupe_mode = COMPONENT_DUPE_UNIQUE_PASSARGS

/datum/component/artifact/Initialize(rarity = ART_RARITY_COMMON)
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE
	RegisterSignal(parent, COMSIG_ITEM_ARTIFACT_GET_EFFECTS, .proc/get_effects)
	RegisterSignal(parent, COMSIG_ITEM_ARTIFACT_EXISTS, .proc/hi)
	RegisterSignal(parent, COMSIG_ITEM_ARTIFACT_MAKE_UNIQUE, .proc/make_unique)
	RegisterSignal(parent, COMSIG_ITEM_ARTIFACT_IDENTIFIED, .proc/is_identified)
	RegisterSignal(parent, COMSIG_ITEM_ARTIFACT_ADD_EFFECT, .proc/add_effect)
	RegisterSignal(parent, COMSIG_ATOM_GET_VALUE, .proc/tabulate_value)
	RegisterSignal(parent, COMSIG_ATOM_ENTERED, .proc/consider_processing)
	// RegisterSignal(parent, COMSIG_ITEM_CLICKED, .proc/on_clicked)
	// RegisterSignal(parent, COMSIG_ITEM_MICROWAVE_ACT, .proc/on_microwave) //c:
	RegisterSignal(parent, COMSIG_ATOM_GET_EXAMINE_NAME, .proc/get_name)
	RegisterSignal(parent, COMSIG_PARENT_EXAMINE, .proc/get_description)
	src.rarity = rarity

/// Runs the artifact's main loop. starts when touched by a mob, stops when it doesnt have anything to do
/datum/component/artifact/process()
	mainloop()
	update_identification()

/datum/component/artifact/proc/mainloop(force_flags)
	ART_MASTER
	var/update_flags = update_everything() | force_flags
	var/atom/current_holder = GET_WEAKREF(current_location)
	var/mob/living/current_target = GET_WEAKREF(affecting)
	for(var/datum/artifact_effect/effect in effects)
		effect.tick(master, current_target, current_holder, current_slot, update_flags)

/datum/component/artifact/proc/update_everything()
	. = NONE
	. |= update_holder()
	. |= update_mob()
	. |= update_slot()
	. |= consider_processing()

/datum/component/artifact/proc/update_mob()
	. = NONE
	var/mob/living/current = GET_WEAKREF(affecting)
	var/mob/living/newbie = recursive_loc_path_search(GET_WEAKREF(current_location), /mob/living)
	if(current == newbie)
		return
	. |= ART_MOB_CHANGED
	affecting = WEAKREF(newbie) // can be null
	if(isliving((newbie)))
		unregister_mob_signals(current)
		register_mob_signals(newbie)

/datum/component/artifact/proc/update_name()
	if(!LAZYLEN(effects))
		return
	if(unique_tag)
		return // handles elsewhere
	ART_MASTER
	unidentified_prefix = null
	identified_prefix = null
	identified_suffix = null
	rare_name = null
	if(rarity == ART_RARITY_COMMON)
		identified_preposition = null
	else
		identified_preposition = "The"
	unidentified_prefix = "[pick(SSartifacts.prefixes_unidentified)] "
	if(rarity >= ART_RARITY_RARE)
		var/helicopter_precum = "[capitalize(pick(SSartifacts.rare_prefixes))]"
		var/helicopter_afterglow = "[capitalize(pick(SSartifacts.rare_suffixes))]"
		rare_name = "[helicopter_precum] [helicopter_afterglow]"
		return
	var/max_prefixes = SSartifacts.max_prefixes_by_rarity[rarity]
	var/max_suffixes = SSartifacts.max_suffixes_by_rarity[rarity]
	var/list/prefixlist = list()
	var/list/suffixlist = list()
	for(var/i in 1 to min(max_prefixes + max_suffixes, LAZYLEN(effects)))
		var/datum/artifact_effect/effect = LAZYACCESS(effects, i)
		if(prob(75) && LAZYLEN(prefixlist) < max_prefixes)
			prefixlist += effect.get_prefix()
		else if(LAZYLEN(suffixlist) < max_suffixes)
			suffixlist += effect.get_suffix()
	identified_prefix = prefixlist.Join(" ")
	identified_prefix = "[identified_prefix] "
	identified_suffix = english_list(suffixlist, "and")
	identified_suffix = " [identified_suffix]"

/datum/component/artifact/proc/register_mob_signals(mob/living/newbie)
	return // todo: this
	//RegisterSignal(newbie, COMSIG_MOB_APPLY_DAMAGE, .proc/on_mob_damage)
	//RegisterSignal(newbie, COMSIG_CARBON_GET_BLEED_MOD, .proc/on_bleed)

/datum/component/artifact/proc/unregister_mob_signals(mob/living/current)
	return // todo: this
	//UnregisterSignal(current, COMSIG_CARBON_GET_BLEED_MOD)

/datum/component/artifact/proc/update_holder()
	. = NONE
	ART_MASTER
	var/atom/prev_loc = GET_WEAKREF(current_location)
	var/atom/new_loc = master.loc
	current_location = WEAKREF(new_loc)
	if(prev_loc != new_loc)
		. |= ART_HOLDER_CHANGED

/datum/component/artifact/proc/update_slot()
	var/obj/item/current_place = GET_WEAKREF(current_location)
	var/prev_slot = current_slot
	if(!isitem(current_place))
		current_slot = null
	else
		current_slot = current_place.current_equipped_slot
	if(prev_slot != current_slot)
		. |= ART_SLUT_CHANGED

/datum/component/artifact/proc/update_identification()
	var/mob/hodler = GET_WEAKREF(affecting)
	if(!hodler)
		return
	if(!hodler.ckey)
		return
	if(is_identified(hodler))
		return // already identified it!
	var/datum/counter_holder/id_plz = LAZYACCESS(identifying, ckey(hodler.ckey))
	if(!id_plz)
		id_plz = new(ART_IDENT_TIME, ART_IDENT_MAX_DELTA) // its 2 vars and I hate lists. wouldnt look it from the fuckhuge overrides list but man, how am I gonna pass all that polymorphic fuckdata in without more shitcode? its already up to my knees
		identifying[ckey(hodler.ckey)] = id_plz
	if(id_plz.check_complete())
		qdel(id_plz)
		identifying[ckey(hodler.ckey)] = null
		identifying -= ckey(hodler.ckey)
		identified_by += ckey(hodler.ckey)
		return TRUE // yay!
	id_plz.tick()

/datum/component/artifact/proc/consider_processing()
	if(CHECK_BITFIELD(process_flags, ART_PROCESS_NEEDS_MOB))
		var/mob/living/someone = GET_WEAKREF(affecting)
		if(!isliving(someone))
			stop_processing()
			return
		ART_MASTER
		if(!recursive_loc_search(master, someone))
			stop_processing()
			return
	start_processing()

/datum/component/artifact/proc/stop_processing()
	for(var/datum/artifact_effect/effect in effects)
		effect.cleanup()
	affecting = null
	STOP_PROCESSING(SSartifacts, src)

/datum/component/artifact/proc/start_processing()
	if(CHECK_BITFIELD(datum_flags, DF_ISPROCESSING))
		return
	START_PROCESSING(SSartifacts, src)

/datum/component/artifact/proc/tabulate_value()
	var/total_value = 0
	for(var/datum/artifact_effect/AE in effects)
		total_value += AE.get_value()
	total_value /= max(LAZYLEN(effects), 1)
	return total_value

/datum/component/artifact/proc/get_name(mob/user, list/override)
	if(!ismob(user))
		return
	if(!is_identified(src, user))
		override[EXAMINE_POSITION_PREFIX] = unidentified_prefix
		return TRUE
	if (rare_name)
		override[EXAMINE_POSITION_NAME] = rare_name
		return TRUE
	override[EXAMINE_POSITION_PREFIX] = identified_prefix
	override[EXAMINE_POSITION_SUFFIX] = identified_suffix
	return TRUE

/datum/component/artifact/proc/get_description(datum/source, mob/user, list/examine_list)
	if(!is_identified(source, user))
		examine_list += "[unidentified_desc]"
		return
	var/list/descs = list()
	for(var/datum/artifact_effect/AE in effects)
		descs |= AE.get_desc()
	var/out = descs.Join("\n")
	examine_list += out

/datum/component/artifact/proc/is_identified(datum/source, mob/user)
	if(IsAdminGhost(user))
		return TRUE
	if((user?.mind?.assigned_role) in identify_jobs)
		return TRUE
	if(user.ckey in identified_by)
		return TRUE

/datum/component/artifact/proc/hi()
	return TRUE // hi

/datum/component/artifact/proc/get_effects(datum/source, list/fx)
	fx |= effects
	return TRUE // hi~

/datum/component/artifact/proc/add_effect(datum/source, datum/artifact_effect/AE_path, rarity, isbuff, list/parameters = list())
	ART_MASTER
	var/datum/artifact_effect/effect = new AE_path(master, parameters)
	effect.randomize(rarity, isbuff)
	effects |= effect
	update_everything()
	update_name()

/datum/component/artifact/proc/make_unique(datum/source, datum/artifact_unique/AU) // effects already appplied, now gussy up the itussy
	ART_MASTER
	unique_tag = AU.key
	identified_preposition = "The"
	unidentified_prefix = "\a"
	identified_prefix = null
	identified_suffix = null
	identified_name = AU.true_name
	//unidentified_name = AU.name
	identified_desc = AU.true_desc
	//unidentified_desc = AU.desc
	value = AU.value
	update_image(AU.icon, AU.icon_state, AU.color, AU.use_alternate_appearance)

/datum/component/artifact/proc/update_image(cool_icon, cool_icon_state, cool_color, use_aa)
	ART_MASTER
	if(use_aa)
		var/image/ID_img
		if(isicon(cool_icon))
			ID_img = image(cool_icon, master, cool_icon_state, master.layer + 1)
		else
			ID_img = image(master.appearance, loc = master, layer = master.layer + 1)
		ID_img.color = cool_color
		master.add_alt_appearance(/datum/atom_hud/alternate_appearance/basic/artifact, "artifact-[unique_tag]", ID_img)
	else
		master.icon = cool_icon
		master.icon_state = cool_icon_state
		master.add_atom_colour(cool_color, FIXED_COLOUR_PRIORITY)

/datum/export/artifact
	cost = 1000
	unit_name = "artifacts"
	export_types = list(/obj/item/artifact)

//ratio of 3 to 1 positive to negative is based on low artifacts where negative can be up to three times more than positive
/datum/export/artifact/get_cost(atom/movable/AM)
	return SEND_SIGNAL(AM, COMSIG_ITEM_GET_COST)
	// var/obj/item/artifact/H = AM
	// return (H.buff_strength*3 - H.debuff_strength)*10 //only change the last number to adjust value

/* 
  ///////////////////////////////////////////
 ////////////////////////////////////////////
/////////////////////////////////////////////
///  _____   _____    _____    _____    /////
/// |  ____| |  __ \  |  __ \  |  __ \  /////
/// | |__    | |__) | | |__) | | |__) | /////
/// |  __|   |  _  /  |  _  /  |  ___/  /////
/// | |____  | | \ \  | | \ \  | |      /////
/// |______| |_|  \_\ |_|  \_\ |_|      //// just imagine that says effects
///////////////////////////////////////////
 */
#define EFFECT_MASTER var/obj/item/master = GET_WEAKREF(my_parent); if(!isitem(master)) CRASH("Artifact effect has no master!!!")
////////////////////////////
/// The actual effectors ///
/datum/artifact_effect
	var/is_buff = FALSE
	var/kind = "none"
	var/name = "Some kind of effect"
	var/list/descriptions = list()
	var/mycolor = "#FFFFFF"
	var/list/desired_slots = list(SLOT_WEAR_SUIT)
	var/desired_slots_string = "Your Butt"
	var/current_slot
	var/datum/weakref/current_location
	var/prefered_container = /obj/item/clothing/suit
	var/target_path = /mob/living
	/// Mob we've applied our equip/dequip effects to
	var/datum/weakref/applied_effects_to
	var/datum/weakref/my_parent
	var/implanted = FALSE
	var/last_applied = 0
	var/allow_dupes = FALSE
	var/prefix = "Parental"
	var/suffix = "Parenthood"
	var/is_only_harmful = FALSE
	var/is_only_helpful = FALSE
	var/chance_weight = 1
	var/special_spawn_only = FALSE
	var/minimum_rarity_to_spawn = ART_RARITY_COMMON
	var/my_unique_trait_id = ""
	var/list/overridden = list()
	var/value = 0
	var/base_value = 0

/datum/artifact_effect/New(obj/item/parent, list/parameters = list())
	. = ..()
	if(!isitem(parent))
		if(!istype(parent, /datum/controller/subsystem/processing/artifacts))
			CRASH("artifact given a fuckin bad thing that shouldnt beeeeee!")
		return
	my_parent = WEAKREF(parent)
	apply_parameters(parameters)
	generate_trait()
	update_desc()
	RegisterSignal(parent, COMSIG_PARENT_PREQDELETED, .proc/on_effect_deleted, TRUE)

/datum/artifact_effect/Del()
	cleanup(TRUE)
	. = ..()

/datum/artifact_effect/proc/generate_trait()
	my_unique_trait_id = "trait_artifact_equipped_[kind]_[rand(1000000, 9999999)]"

/datum/artifact_effect/proc/on_effect_deleted()
	cleanup(TRUE)

/datum/artifact_effect/proc/cleanup(everything)
	var/mob/living/target = GET_WEAKREF(applied_effects_to)
	var/atom/master = GET_WEAKREF(my_parent)
	if(istype(target) && istype(master))
		remove_status_effect(master, target, master.loc)
	applied_effects_to = null
	if(everything)
		current_location = null
		my_parent = null

/datum/artifact_effect/proc/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_NAME)))
		name = LAZYACCESS(parameters, ARTVAR_NAME)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_DESIRED_SLOTS)))
		desired_slots = LAZYACCESS(parameters, ARTVAR_DESIRED_SLOTS)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_PREFERED_CONTAINER)))
		prefered_container = LAZYACCESS(parameters, ARTVAR_PREFERED_CONTAINER)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TARGET_PATH)))
		target_path = LAZYACCESS(parameters, ARTVAR_TARGET_PATH)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_IS_BUFF)))
		is_buff = LAZYACCESS(parameters, ARTVAR_IS_BUFF)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_KIND))) // dont use this one
	// 	kind = LAZYACCESS(parameters, ARTVAR_KIND)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_ALLOW_DUPES)))
		allow_dupes = LAZYACCESS(parameters, ARTVAR_ALLOW_DUPES)
	overridden = parameters.Copy()
	update_name()
	update_color()

/datum/artifact_effect/proc/tick(obj/item/master, mob/living/target, obj/item/holder, parent_slot, update_flags)
	/// ensures we only apply and remove effects once
	var/application_flags = NONE
	/// these handle the equip/dequip effects
	if(CHECK_BITFIELD(update_flags, ART_MOB_CHANGED))
		update_mob(master, target, holder, parent_slot)
	if(CHECK_BITFIELD(update_flags, ART_HOLDER_CHANGED))
		update_location(master, target, holder, parent_slot)
	if(CHECK_BITFIELD(update_flags, ART_SLUT_CHANGED))
		update_slut(master, target, holder, parent_slot)
	return on_tick(master, target, holder)

/// compares where we were to where we are now, and updates our current location
/datum/artifact_effect/proc/update_mob(obj/item/master, mob/living/target, obj/item/holder, parent_slot)
	var/mob/living/prev_mob = GET_WEAKREF(applied_effects_to)
	var/mob/living/new_mob = target
	if(prev_mob == new_mob)
		return
	/// We've affecting a new person!
	if(istype(new_mob, target_path))
		. |= remove_status_effect(master, prev_mob, holder) // will update applied_effects_to
		. |= apply_status_effect(master, new_mob, holder) // will update applied_effects_to
	/// We're no longer affecting the other person!
	if(istype(prev_mob, target_path))
		. |= remove_status_effect(master, new_mob, holder)

/// compares where we were to where we are now, and updates our current location
/datum/artifact_effect/proc/update_location(obj/item/master, mob/living/target, obj/item/holder, parent_slot, application_flags)
	var/atom/prev_loc = GET_WEAKREF(current_location)
	var/atom/new_loc = holder
	if(prev_loc == new_loc) // Alrady there!
		return
	if(istype(prev_loc, prefered_container))
		remove_container_effect(master, prev_loc, holder)
	if(istype(new_loc, prefered_container))
		apply_container_effect(master, new_loc, holder)
	current_location = WEAKREF(new_loc)

/// compares where we were to where we are now, and updates our current slot
/datum/artifact_effect/proc/update_slut(obj/item/master, mob/living/target, obj/item/holder, parent_slot, application_flags)
	if(parent_slot == current_slot)
		return // already where we should be
	var/am_in_desired_slot = (current_slot in desired_slots)
	var/going_to_desired_slot = (parent_slot in desired_slots)
	if(am_in_desired_slot && !going_to_desired_slot)
		. |= remove_status_effect(master, target, holder)
	if(!am_in_desired_slot && going_to_desired_slot)
		. |= apply_status_effect(master, target, holder)
	current_slot = parent_slot

/// Applies our statud effect, if any
/datum/artifact_effect/proc/apply_status_effect(obj/item/master, mob/living/target, obj/item/holder)
	if(HAS_TRAIT(target, my_unique_trait_id)) // already affecting them!
		return
	return on_equipped(master, target, holder)

/// Applies our statud effect, if any
/datum/artifact_effect/proc/remove_status_effect(obj/item/master, mob/living/target, obj/item/holder)
	if(!HAS_TRAIT(target, my_unique_trait_id)) // we arent affecting them!
		return
	return on_unequipped(master, target, holder)

/// Applies our statud effect, if any
/datum/artifact_effect/proc/apply_container_effect(obj/item/master, mob/living/target, obj/item/holder)
	var/mob/living/current = GET_WEAKREF(current_location)
	if(current == target) // already affecting them!
		return
	return on_equipped(master, target, holder)

/// Applies our statud effect, if any
/datum/artifact_effect/proc/remove_container_effect(obj/item/master, mob/living/target, obj/item/holder)
	var/atom/current = GET_WEAKREF(current_location)
	if(current != holder) // We werent affecting them!
		return
	return on_removed(master, target, holder)

/// Searches thrugh the parents loc for something worn by a mob
/// Returns the slot it was found in, null if not found
/datum/artifact_effect/proc/get_slot(obj/item/recur)
	if(!isitem(recur))
		return
	if(recur.current_equipped_slot)
		return recur.current_equipped_slot
	if(isitem(recur.loc))
		return get_slot(recur.loc)

/////////////////////////////////////////////////
/// The actual effect of the thing
/datum/artifact_effect/proc/on_inserted(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/////////////////////////////////////////////////
/// Prescreen to see if the effect should effect
/datum/artifact_effect/proc/on_removed(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/////////////////////////////////////////////////
/// The actual effect of the thing
/datum/artifact_effect/proc/on_equipped(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/////////////////////////////////////////////////
/// The actual effect of the thing
/datum/artifact_effect/proc/on_unequipped(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/////////////////////////////////////////////////
/// The actual effect of the thing
/datum/artifact_effect/proc/on_tick()
	return TRUE

/// Generic mob-targetted pre-screener
/datum/artifact_effect/proc/check_armor(mob/living/target, armorflag = "melee", zone)
	if(!isliving(target)) // currently all effects affect the living
		return 0
	if(implanted)
		return 0 // implants dont care about armor
	return target.getarmor(zone, armorflag)

/// Generic mob-targetted pre-screener
/datum/artifact_effect/proc/check_dt(mob/living/target, zone)
	if(!isliving(target)) // currently all effects affect the living
		return 0
	if(implanted)
		return 0 // implants dont care about armor
	return target.getarmor(zone, "damage_threshold")

/datum/artifact_effect/proc/send_message(mob/living/target, damtype)
	return

/datum/artifact_effect/proc/get_prefix()
	return prefix

/datum/artifact_effect/proc/get_suffix()
	return suffix

/datum/artifact_effect/proc/get_desc()
	if(!LAZYLEN(descriptions))
		update_desc()
	return descriptions

/datum/artifact_effect/proc/randomize(rarity, force_buff)
	update_name()
	update_color()
	return TRUE

/datum/artifact_effect/proc/update_color()
	return

/datum/artifact_effect/proc/update_name()
	update_prefix()
	update_suffix()

/datum/artifact_effect/proc/update_desc()
	descriptions = list("This is a generic artifact effect. It does nothing.")
	return

/datum/artifact_effect/proc/update_value()
	value = (base_value * get_magnitude())

/datum/artifact_effect/proc/update_prefix()
	prefix = "Parental"

/datum/artifact_effect/proc/update_suffix()
	suffix = "Parenthood"

/datum/artifact_effect/proc/get_magnitude() // pop pop
	return 1

/datum/artifact_effect/proc/get_value()
	return value

/datum/artifact_effect/proc/translate_slots()
	var/list/ret = list()
	for(var/slot in desired_slots)
		ret += list(slotdefine2text(slot))
	desired_slots_string = english_list(ret, and_text = "or")

/datum/artifact_effect/proc/slotdefine2text(slut)
	switch(slut)
		if(SLOT_BACK)
			return "on your back"
		if(SLOT_WEAR_MASK)
			return "on your face"
		if(SLOT_HANDCUFFED)
			return "somehow handcuffed to you"
		if(SLOT_HANDS)
			return "in your hands"
		if(SLOT_BELT)
			return "in or on your belt"
		if(SLOT_WEAR_ID)
			return "in your wallet slot"
		if(SLOT_EARS)
			return "over your ears"
		if(SLOT_GLASSES)
			return "over your eyes"
		if(SLOT_GLOVES)
			return "around your hands"
		if(SLOT_NECK)
			return "around your neck"
		if(SLOT_HEAD)
			return "on your head"
		if(SLOT_SHOES)
			return "around your feetpaws"
		if(SLOT_WEAR_SUIT)
			return "in or as a suit"
		if(SLOT_W_UNIFORM)
			return "in or as clothing"
		if(SLOT_L_STORE)
			return "in your left pocket"
		if(SLOT_R_STORE)
			return "in your right pocket"
		if(SLOT_S_STORE)
			return "in your gunholder"
		if(SLOT_IN_BACKPACK)
			return "in your backpack"
		if(SLOT_LEGCUFFED)
			return "as legcuffs somehow"
		if(SLOT_GENERIC_DEXTROUS_STORAGE)
			return "held by a wretched creature"

/datum/artifact_effect/proc/in_desired_slot()
	EFFECT_MASTER
	return ((master.current_equipped_slot) in desired_slots)

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
//// MAX HP MODIFIER ////
/datum/artifact_effect/max_hp_modifier
	kind = ARTMOD_MAX_HP
	base_value = 300
	chance_weight = 1
	var/hp_change = 0
	var/equip_message = "You feel stronger."
	var/unequip_message = "You feel weaker."

/datum/artifact_effect/max_hp_modifier/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_HP_CHANGE)))
		hp_change = LAZYACCESS(parameters, ARTVAR_HP_CHANGE)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_EQUIP_MESSAGE)))
		equip_message = LAZYACCESS(parameters, ARTVAR_EQUIP_MESSAGE)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_UNEQUIP_MESSAGE)))
		unequip_message = LAZYACCESS(parameters, ARTVAR_UNEQUIP_MESSAGE)
	is_buff = (hp_change > 0)
	. = ..()

/datum/artifact_effect/max_hp_modifier/on_equipped(obj/item/master, mob/living/target, obj/item/holder)
	target.maxHealth += hp_change
	target.adjustBruteLoss(hp_change)
	return TRUE

/datum/artifact_effect/max_hp_modifier/on_unequipped(obj/item/master, mob/living/target, obj/item/holder)
	target.maxHealth -= hp_change
	target.adjustBruteLoss(-hp_change)
	return TRUE

/datum/artifact_effect/max_hp_modifier/randomize(rarity, force_buff)
	if(isnull(LAZYACCESS(overridden, ARTVAR_HP_CHANGE)))
		switch(rarity)
			if(ART_RARITY_COMMON)
				hp_change = rand((force_buff ? 0 : SSartifacts.health_common_minimum), SSartifacts.health_common_maximum)
			if(ART_RARITY_UNCOMMON)
				hp_change = rand((force_buff ? 0 : SSartifacts.health_uncommon_minimum), SSartifacts.health_uncommon_maximum)
			if(ART_RARITY_RARE)
				hp_change = rand((force_buff ? 0 : SSartifacts.health_rare_minimum), SSartifacts.health_rare_maximum)
	hp_change = round(hp_change, SSartifacts.health_discrete)
	is_buff = (hp_change > 0)
	. = ..()

/datum/artifact_effect/max_hp_modifier/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_health_good) * (abs(hp_change) / SSartifacts.health_rare_maximum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_health_good) * (abs(hp_change) / SSartifacts.health_rare_maximum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_health_bad) * (abs(hp_change) / abs(SSartifacts.health_rare_minimum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_health_bad) * (abs(hp_change) / abs(SSartifacts.health_rare_minimum)), 1)
	return possy

/datum/artifact_effect/max_hp_modifier/update_prefix()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.prefixes_health_good) : LAZYLEN(SSartifacts.prefixes_health_bad))
	prefix = LAZYACCESS(is_buff ? SSartifacts.prefixes_health_good : SSartifacts.prefixes_health_bad, index)
	return prefix

/datum/artifact_effect/max_hp_modifier/update_suffix()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.suffixes_health_good) : LAZYLEN(SSartifacts.suffixes_health_bad))
	suffix = LAZYACCESS(is_buff ? SSartifacts.suffixes_health_good : SSartifacts.suffixes_health_bad, index)
	return suffix

/datum/artifact_effect/max_hp_modifier/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Increases your maximum health by [hp_change] points when stored [desired_slots_string].")
	else
		out += span_alert("Decreases your maximum health by [abs(hp_change)] points when stored [desired_slots_string].")
	descriptions = out

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
//// TRAIT GIVER ////
/// Gives a trait, mainly for uniques ///
/datum/artifact_effect/trait_giver
	kind = ARTMOD_TRAIT_GIVER
	base_value = 300
	chance_weight = 0
	special_spawn_only = TRUE
	var/custom_prefix = "Trait"
	var/custom_suffix = "Giver"
	var/custom_desc = "Gives you a trait when stored somewhere."
	var/trait_to_give

/datum/artifact_effect/trait_giver/penance
	kind = ARTMOD_TRAIT_GIVER_PENANCE
	base_value = 300
	custom_desc = span_alert("Causes intense suffering to the wearer.")
	trait_to_give = TRAIT_PENANCE

/datum/artifact_effect/trait_giver/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TRAIT_TO_GIVE)))
		trait_to_give = LAZYACCESS(parameters, ARTVAR_TRAIT_TO_GIVE)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_CUSTOM_PREFIX)))
		custom_prefix = LAZYACCESS(parameters, ARTVAR_CUSTOM_PREFIX)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_CUSTOM_SUFFIX)))
		custom_suffix = LAZYACCESS(parameters, ARTVAR_CUSTOM_SUFFIX)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_CUSTOM_DESC)))
		custom_desc = LAZYACCESS(parameters, ARTVAR_CUSTOM_DESC)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_IS_BUFF)))
		is_buff = LAZYACCESS(parameters, ARTVAR_IS_BUFF) // manually assigned
	. = ..()

/datum/artifact_effect/trait_giver/on_equipped(obj/item/master, mob/living/target, obj/item/holder)
	ADD_TRAIT(target, trait_to_give, src)
	return TRUE

/datum/artifact_effect/trait_giver/on_unequipped(obj/item/master, mob/living/target, obj/item/holder)
	REMOVE_TRAIT(target, trait_to_give, src)
	return TRUE

/datum/artifact_effect/trait_giver/randomize(rarity, force_buff)
	. = ..()

/datum/artifact_effect/trait_giver/get_magnitude(isprefix)
	return 1

/datum/artifact_effect/trait_giver/update_prefix()
	return custom_prefix

/datum/artifact_effect/trait_giver/update_suffix()
	return custom_suffix

/datum/artifact_effect/trait_giver/update_desc()
	descriptions = list(custom_desc)

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
//// TIMER ////
/// Counts up while in its desired slot to a certain amount, then does a thing
/// what thing? thats up to you! ///
/datum/artifact_effect/timer
	kind = ARTMOD_TIMER
	base_value = 300
	chance_weight = 0
	special_spawn_only = TRUE
	var/custom_desc = "Counts up while in its desired slot to a certain amount, then does a thing."
	var/target_time = 10 MINUTES
	var/max_delta = 30 SECONDS
	var/list/counters = list()

/datum/artifact_effect/timer/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TARGET_TIME)))
		target_time = LAZYACCESS(parameters, ARTVAR_TARGET_TIME)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_MAX_DELTA)))
		max_delta = LAZYACCESS(parameters, ARTVAR_MAX_DELTA)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_IS_BUFF)))
		is_buff = LAZYACCESS(parameters, ARTVAR_IS_BUFF) // manually assigned
	. = ..()

/datum/artifact_effect/timer/on_equipped(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/datum/artifact_effect/timer/on_unequipped(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/datum/artifact_effect/timer/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	if(!timer_condition(master, target, holder))
		return
	var/ckye = target.ckey
	var/datum/counter_holder/CH = LAZYACCESS(counters, ckye)
	if(!istype(CH))
		CH = new(target_time, max_delta)
		counters[ckye] = CH
	if(CH.is_complete())
		return // already did the thing
	CH.tick()
	if(!CH.check_completion())
		return
	return do_thing(master, target, holder)

/datum/artifact_effect/timer/proc/timer_condition(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return FALSE
	if(!target.ckey)
		return FALSE
	if(!in_desired_slot(master, target, holder))
		return FALSE
	return TRUE

/datum/artifact_effect/timer/proc/do_thing(obj/item/master, mob/living/target, obj/item/holder)
	return TRUE

/datum/artifact_effect/timer/randomize(rarity, force_buff)
	. = ..()

/datum/artifact_effect/timer/get_magnitude(isprefix)
	return 1

/datum/artifact_effect/timer/update_prefix()
	return

/datum/artifact_effect/timer/update_suffix()
	return

/datum/artifact_effect/timer/update_desc()
	descriptions = list(custom_desc)

//// TIMER ////
/// Counts up while in its desired slot to a certain amount, then does a thing
/// what thing? thats up to you! ///
/datum/artifact_effect/timer/penance
	kind = ARTMOD_TIMER_PENANCE
	base_value = 1000
	chance_weight = 0
	special_spawn_only = TRUE
	custom_desc = span_alert("Might do something if you hold on to it?")
	target_time = ART_PENANCE_TIME
	max_delta = 2 SECONDS

/datum/artifact_effect/timer/penance/do_thing(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	ADD_TRAIT(target, TRAIT_PENANCE_COMPLETE, src)
	return TRUE


///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
//// SPEED MODIFIER ////
/datum/artifact_effect/speed
	kind = ARTMOD_SPEED
	base_value = 400
	chance_weight = 1
	var/multiplicative_slowdown = 0 // more is slower
	var/my_unique_id = "bingus"
	var/equip_message = "You feel faster."
	var/unequip_message = "You feel slower."

/datum/artifact_effect/speed/New()
	. = ..()
	my_unique_id = "speed_[world.time]_[rand(1000000, 9999999)]"

/datum/artifact_effect/speed/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_SLOWDOWN)))
		multiplicative_slowdown = LAZYACCESS(parameters, ARTVAR_SLOWDOWN)
	is_buff = (multiplicative_slowdown < 0)
	. = ..()

/datum/artifact_effect/speed/randomize(rarity, force_buff)
	if(isnull(LAZYACCESS(overridden, ARTVAR_SLOWDOWN)))
		switch(rarity)
			if(ART_RARITY_COMMON)
				multiplicative_slowdown = rand(SSartifacts.speed_common_minimum, force_buff ? 0 : SSartifacts.speed_common_maximum)
			if(ART_RARITY_UNCOMMON)
				multiplicative_slowdown = rand(SSartifacts.speed_uncommon_minimum, force_buff ? 0 : SSartifacts.speed_uncommon_maximum)
			if(ART_RARITY_RARE)
				multiplicative_slowdown = rand(SSartifacts.speed_rare_minimum, force_buff ? 0 : SSartifacts.speed_rare_maximum)
	multiplicative_slowdown = round(multiplicative_slowdown, SSartifacts.speed_discrete)
	is_buff = (multiplicative_slowdown < 0)
	. = ..()

/datum/artifact_effect/speed/on_equipped(obj/item/master, mob/living/target, obj/item/holder)
	target.add_movespeed_modifier(/datum/movespeed_modifier/artifact_slowness, update = TRUE, cool_id = my_unique_id)
	return TRUE

/datum/artifact_effect/speed/on_unequipped(obj/item/master, mob/living/target, obj/item/holder)
	target.remove_movespeed_modifier(my_unique_id, update = TRUE)
	return TRUE

/datum/artifact_effect/speed/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_speed_good) * (abs(multiplicative_slowdown) / SSartifacts.speed_rare_maximum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_speed_good) * (abs(multiplicative_slowdown) / SSartifacts.speed_rare_maximum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_speed_bad) * (abs(multiplicative_slowdown) / abs(SSartifacts.speed_rare_minimum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_speed_bad) * (abs(multiplicative_slowdown) / abs(SSartifacts.speed_rare_minimum)), 1)
	return possy

/datum/artifact_effect/speed/update_prefix()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.prefixes_speed_good) : LAZYLEN(SSartifacts.prefixes_speed_bad))
	prefix = LAZYACCESS(is_buff ? SSartifacts.prefixes_speed_good : SSartifacts.prefixes_speed_bad, index)
	return prefix

/datum/artifact_effect/speed/update_suffix()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.suffixes_speed_good) : LAZYLEN(SSartifacts.suffixes_speed_bad))
	suffix = LAZYACCESS(is_buff ? SSartifacts.suffixes_speed_good : SSartifacts.suffixes_speed_bad, index)
	return suffix

/datum/artifact_effect/speed/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Increases your movement speed by [abs(multiplicative_slowdown)] when stored [desired_slots_string].")
	else
		out += span_alert("Decreases your movement speed by [abs(multiplicative_slowdown)] when stored [desired_slots_string].")
	descriptions = out

/datum/movespeed_modifier/artifact_slowness
	flags = IGNORE_NOSLOW
	variable = TRUE

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// PASSIVE DAMAGE DEALER                     ///
/// Dont use for healing, it just wont work  ///
/// All values are in damage per second     ///
/datum/artifact_effect/passive_damage
	kind = ARTMOD_PASSIVE_DOT
	chance_weight = 5
	/// Stop doing damage if their health is below this
	var/min_health = 5
	/// Damage to do to brute
	var/d_brute = 0
	/// Damage to do to burn
	var/d_burn = 0
	/// Damage to do to toxin
	var/d_toxin = 0
	/// Damage to do to oxy
	var/d_oxy = 0
	/// Damage to do to clone
	var/d_clone = 0
	/// Damage to do to brain
	var/d_brain = 0
	/// if we're in a slot that isnt prefered, we do more damage uwu
	var/undesirable_mult = 2
	var/is_dps = TRUE
	var/too_injured = "%SRC is unable to harm you any further."
	var/injured = "%SRC is harming you."
	var/armor_flag = "melee"
	var/highest_damage = BRUTE
	base_value = 1000 // it'll do damage anywhere in your inventory, so, should be worth something!
	allow_dupes = TRUE
	is_only_harmful = TRUE
	is_only_helpful = FALSE

/datum/artifact_effect/passive_damage/apply_parameters(list/parameters = list())
	var/damage_preset = FALSE
	var/damage_minmax_preset = FALSE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_MIN_HEALTH)))
		min_health = LAZYACCESS(parameters, ARTVAR_MIN_HEALTH)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_BRUTE)))
		d_brute = LAZYACCESS(parameters, ARTVAR_BRUTE)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_BURN)))
		d_burn = LAZYACCESS(parameters, ARTVAR_BURN)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TOXIN)))
		d_toxin = LAZYACCESS(parameters, ARTVAR_TOXIN)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_OXY)))
		d_oxy = LAZYACCESS(parameters, ARTVAR_OXY)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_CLONE)))
		d_clone = LAZYACCESS(parameters, ARTVAR_CLONE)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_BRAIN)))
		d_brain = LAZYACCESS(parameters, ARTVAR_BRAIN)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_IS_DPS)))
		is_dps = LAZYACCESS(parameters, ARTVAR_IS_DPS)
		damage_preset = TRUE
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TOO_INJURED)))
		too_injured = LAZYACCESS(parameters, ARTVAR_TOO_INJURED)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_INJURED)))
		injured = LAZYACCESS(parameters, ARTVAR_INJURED)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_ARMOR_FLAG)))
		armor_flag = LAZYACCESS(parameters, ARTVAR_ARMOR_FLAG)
	update_highest_damage()
	. = ..()
	if(damage_preset)
		LAZYSET(overridden, ARTFLAG_DAMAGE_PRESET, damage_preset)

/datum/artifact_effect/passive_damage/randomize(rarity, force_buff)
	if(LAZYACCESS(overridden, ARTFLAG_BLOCK_DAMAGE_RANDOM))
		return ..() // =3
	var/list/alltypes = list(BRUTE, BURN, TOX, OXY, CLONE, BRAIN)
	var/num_damages = 0
	if(min_health == initial(min_health))
		switch(rarity)
			if(ART_RARITY_COMMON)
				min_health = SSartifacts.damage_common_cutoff_minimum
			if(ART_RARITY_UNCOMMON)
				min_health = SSartifacts.damage_uncommon_cutoff_minimum
			if(ART_RARITY_RARE)
				min_health = SSartifacts.damage_rare_cutoff_minimum
	if(isnull(LAZYACCESS(overridden, ARTFLAG_DAMAGE_PRESET)))
		switch(rarity)
			if(ART_RARITY_COMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_common) // so, one
			if(ART_RARITY_UNCOMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_uncommon)
			if(ART_RARITY_RARE)
				num_damages = rand(1, SSartifacts.damage_max_types_rare)
		for(var/i in 1 to num_damages)
			var/damtype = pick(alltypes)
			alltypes -= list(damtype)
			switch(damtype)
				if(BRUTE)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_brute = rand(0, SSartifacts.damage_dps_brute_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_brute = rand(0, SSartifacts.damage_dps_brute_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_brute = rand(0, SSartifacts.damage_dps_brute_rare_maximum)
					d_brute = round(d_brute, SSartifacts.damage_discrete)
				if(BURN)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_burn = rand(0, SSartifacts.damage_dps_burn_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_burn = rand(0, SSartifacts.damage_dps_burn_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_burn = rand(0, SSartifacts.damage_dps_burn_rare_maximum)
					d_burn = round(d_burn, SSartifacts.damage_discrete)
				if(TOX)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_toxin = rand(0, SSartifacts.damage_dps_toxin_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_toxin = rand(0, SSartifacts.damage_dps_toxin_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_toxin = rand(0, SSartifacts.damage_dps_toxin_rare_maximum)
					d_toxin = round(d_toxin, SSartifacts.damage_discrete)
				if(OXY)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_oxy = rand(0, SSartifacts.damage_dps_oxy_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_oxy = rand(0, SSartifacts.damage_dps_oxy_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_oxy = rand(0, SSartifacts.damage_dps_oxy_rare_maximum)
					d_oxy = round(d_oxy, SSartifacts.damage_discrete)
				if(CLONE)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_clone = rand(0, SSartifacts.damage_dps_clone_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_clone = rand(0, SSartifacts.damage_dps_clone_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_clone = rand(0, SSartifacts.damage_dps_clone_rare_maximum)
					d_clone = round(d_clone, SSartifacts.damage_discrete)
				if(BRAIN)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_brain = rand(0, SSartifacts.damage_dps_brain_common_maximum)
						if(ART_RARITY_UNCOMMON)
							d_brain = rand(0, SSartifacts.damage_dps_brain_uncommon_maximum)
						if(ART_RARITY_RARE)
							d_brain = rand(0, SSartifacts.damage_dps_brain_rare_maximum)
					d_brain = round(d_brain, SSartifacts.damage_discrete)
	. = ..()

/datum/artifact_effect/passive_damage/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	if(target.health < min_health)
		return
	var/mult = is_dps ? ((world.time - last_applied) * 0.1) : 1
	var/zone = pick(GLOB.main_body_parts)
	var/dr = 1
	var/dt = 0
	if(!implanted)
		dr = check_armor(target, armor_flag, zone)
		dt = check_dt(target, zone)
	if(implanted || !in_desired_slot())
		mult *= undesirable_mult
	target.apply_damages(
		brute = (d_brute * mult),
		burn  = (d_burn  * mult),
		tox   = (d_toxin * mult),
		oxy   = (d_oxy   * mult),
		clone = (d_clone * mult),
		brain = (d_brain * mult),
		def_zone = zone,
		blocked = dr,
		damagethreshold = dt,
	)
	last_applied = world.time
	//send_message(target, zone)
	return TRUE

/datum/artifact_effect/passive_damage/get_magnitude(isprefix)
	var/possy = 1
	switch(highest_damage)
		if(BRUTE)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_brute) * (abs(d_brute) / SSartifacts.damage_dps_brute_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_brute) * (abs(d_brute) / SSartifacts.damage_dps_brute_rare_maximum), 1)
		if(BURN)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_burn) * (abs(d_burn) / SSartifacts.damage_dps_burn_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_burn) * (abs(d_burn) / SSartifacts.damage_dps_burn_rare_maximum), 1)
		if(TOX)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_toxin) * (abs(d_toxin) / SSartifacts.damage_dps_toxin_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_toxin) * (abs(d_toxin) / SSartifacts.damage_dps_toxin_rare_maximum), 1)
		if(OXY)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_oxy) * (abs(d_oxy) / SSartifacts.damage_dps_oxy_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_oxy) * (abs(d_oxy) / SSartifacts.damage_dps_oxy_rare_maximum), 1)
		if(CLONE)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_clone) * (abs(d_clone) / SSartifacts.damage_dps_clone_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_clone) * (abs(d_clone) / SSartifacts.damage_dps_clone_rare_maximum), 1)
		if(BRAIN)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_damage_brain) * (abs(d_brain) / SSartifacts.damage_dps_brain_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_damage_brain) * (abs(d_brain) / SSartifacts.damage_dps_brain_rare_maximum), 1)
	return possy

/datum/artifact_effect/passive_damage/update_prefix()
	update_highest_damage()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	switch(highest_damage)
		if(BRUTE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_brute))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_brute, index)
		if(BURN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_burn))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_burn, index)
		if(TOX)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_toxin))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_toxin, index)
		if(OXY)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_oxy))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_oxy, index)
		if(CLONE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_clone))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_clone, index)
		if(BRAIN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_damage_brain))
			prefix = LAZYACCESS(SSartifacts.prefixes_damage_brain, index)
	return prefix

/datum/artifact_effect/passive_damage/update_suffix()
	update_highest_damage()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	switch(highest_damage)
		if(BRUTE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_brute))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_brute, index)
		if(BURN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_burn))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_burn, index)
		if(TOX)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_toxin))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_toxin, index)
		if(OXY)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_oxy))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_oxy, index)
		if(CLONE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_clone))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_clone, index)
		if(BRAIN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_damage_brain))
			suffix = LAZYACCESS(SSartifacts.suffixes_damage_brain, index)
	return suffix

/datum/artifact_effect/passive_damage/update_desc()
	var/list/out = list()
	var/the_min_health = clamp(min_health, -100, 200)
	if(d_brute)
		out += span_alert("Deals [d_brute] brute damage per second while the wearer is above [the_min_health].")
	if(d_burn)
		out += span_alert("Deals [d_burn] burn damage per second while the wearer is above [the_min_health].")
	if(d_toxin)
		out += span_alert("Deals [d_toxin] toxin damage per second while the wearer is above [the_min_health].")
	if(d_oxy)
		out += span_alert("Deals [d_oxy] oxy damage per second while the wearer is above [the_min_health].")
	if(d_clone)
		out += span_alert("Deals [d_clone] clone damage per second while the wearer is above [the_min_health].")
	if(d_brain)
		out += span_alert("Deals [d_brain] brain damage per second while the wearer is above [the_min_health].")
	out += span_alert("Deals [undesirable_mult]x damage when stored somewhere else.")
	descriptions = out

/datum/artifact_effect/passive_damage/send_message(mob/living/target, damtype)
	if(!prob(1))
		return
	if(target.health < min_health)
		to_chat(target, span_danger("[too_injured]"))
	else
		to_chat(target, span_danger("[injured]"))

/datum/artifact_effect/passive_damage/proc/update_highest_damage()
	highest_damage = BRUTE
	if(d_brute < d_burn)
		highest_damage = BURN
	if(d_burn < d_toxin)
		highest_damage = TOX
	if(d_toxin < d_oxy)
		highest_damage = OXY
	if(d_oxy < d_clone)
		highest_damage = CLONE
	if(d_clone < d_brain)
		highest_damage = BRAIN

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// PASSIVE DAMAGE DEALER - RANDOM TYPE EDITION ///
/datum/artifact_effect/passive_damage/random
	kind = ARTMOD_PASSIVE_DOT_RANDOM
	// var/brute_flavor = "You feel a dull ache."
	// var/burn_flavor = "You feel a burning sensation."
	// var/toxin_flavor = "You feel sick."
	// var/oxy_flavor = "You feel out of breath."
	// var/clone_flavor = "You feel a worrying growth shift about."
	// var/brain_flavor = "Your head aches."

/datum/artifact_effect/passive_damage/random/apply_parameters(list/parameters = list())
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_BRUTE_FLAVOR)))
	// 	brute_flavor = LAZYACCESS(parameters, parm)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_BURN_FLAVOR)))
	// 	burn_flavor = LAZYACCESS(parameters, parm)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_TOXIN_FLAVOR)))
	// 	toxin_flavor = LAZYACCESS(parameters, parm)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_OXY_FLAVOR)))
	// 	oxy_flavor = LAZYACCESS(parameters, parm)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_CLONE_FLAVOR)))
	// 	clone_flavor = LAZYACCESS(parameters, parm)
	// if(!isnull(LAZYACCESS(parameters, ARTVAR_BRAIN_FLAVOR)))
	// 	brain_flavor = LAZYACCESS(parameters, parm)
	. = ..()

/datum/artifact_effect/passive_damage/random/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	if(target.health < min_health)
		return
	var/mult = is_dps ? ((world.time - last_applied) * 0.1) : 1
	var/list/dmgs = list()
	if(d_brute)
		dmgs += list(BRUTE = d_brute * mult)
	if(d_burn)
		dmgs += list(BURN = d_burn * mult)
	if(d_toxin)
		dmgs += list(TOX = d_toxin * mult)
	if(d_oxy)
		dmgs += list(OXY = d_oxy * mult)
	if(d_clone)
		dmgs += list(CLONE = d_clone * mult)
	if(d_brain)
		dmgs += list(BRAIN = d_brain * mult)
	var/list/d_list = pick(dmgs)
	if(!LAZYACCESS(d_list, 2))
		return
	if(implanted || !((get_slot(master)) in desired_slots))
		d_list[2] *= undesirable_mult
	d_list[2] -= check_armor(target, armor_flag)
	d_list[2] *= check_dt(target)
	target.apply_damage(LAZYACCESS(d_list, 2), LAZYACCESS(d_list, 1))
	last_applied = world.time
	//send_message(target, LAZYACCESS(dmg_out, 2))
	return TRUE

/datum/artifact_effect/passive_damage/random/send_message(mob/living/target, damtype, zone)
	// if(!prob(1))
	// 	return
	// var/msg_out = "You hurt."
	// switch(damtype)
	// 	if(BRUTE)
	// 		msg_out = brute_flavor
	// 	if(BURN)
	// 		msg_out = burn_flavor
	// 	if(TOX)
	// 		msg_out = toxin_flavor
	// 	if(OXY)
	// 		msg_out = oxy_flavor
	// 	if(CLONE)
	// 		msg_out = clone_flavor
	// 	if(BRAIN)
	// 		msg_out = brain_flavor
	// to_chat(target, span_danger(msg_out))

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// PASSIVE DAMAGE HEALER                        ///
/// jk it can heal~                             ///
/// make sure the damage vars are negative uwu ///
/// though it forces a negative, sooooo.....  ///
/datum/artifact_effect/passive_damage/healer
	kind = ARTMOD_PASSIVE_HEAL
	chance_weight = 1
	/// Stop healing if their health is below this
	min_health = 5
	/// Stop healing if they're health is above this
	var/max_health = 90
	/// if we're in a slot that isnt prefered, we do less healing uwu. applies to implants!!!
	undesirable_mult = 0.1
	is_dps = TRUE
	armor_flag = "melee"
	allow_dupes = TRUE
	is_only_harmful = FALSE
	is_only_helpful = TRUE

/datum/artifact_effect/passive_damage/healer/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_MAX_HEALTH)))
		max_health = LAZYACCESS(parameters, ARTVAR_MAX_HEALTH)
	is_buff = TRUE // cus it is
	. = ..()

/datum/artifact_effect/passive_damage/healer/randomize(rarity, force_buff)
	overridden[ARTFLAG_BLOCK_DAMAGE_RANDOM] = TRUE
	var/list/alltypes = list(BRUTE, BURN, TOX, OXY, CLONE, BRAIN)
	var/num_damages = 0
	if(min_health == initial(min_health))
		switch(rarity)
			if(ART_RARITY_COMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_common) // so, one
				if(force_buff)
					min_health = SSartifacts.heal_common_minimum_health
				else
					min_health = rand(SSartifacts.heal_common_minimum_health, SSartifacts.heal_common_maximum_health)
			if(ART_RARITY_UNCOMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_uncommon)
				if(force_buff)
					min_health = SSartifacts.heal_uncommon_minimum_health
				else
					min_health = rand(SSartifacts.heal_uncommon_minimum_health, SSartifacts.heal_uncommon_maximum_health)
			if(ART_RARITY_RARE)
				num_damages = rand(1, SSartifacts.damage_max_types_rare)
				if(force_buff)
					min_health = SSartifacts.heal_rare_minimum_health
				else
					min_health = rand(SSartifacts.heal_rare_minimum_health, SSartifacts.heal_rare_maximum_health)
	if(max_health == initial(max_health))
		switch(rarity)
			if(ART_RARITY_COMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_common) // so, one
				if(force_buff)
					max_health = SSartifacts.heal_common_maximum_health
				else
					max_health = rand(min_health, SSartifacts.heal_common_maximum_health)
			if(ART_RARITY_UNCOMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_uncommon)
				if(force_buff)
					max_health = SSartifacts.heal_uncommon_maximum_health
				else
					max_health = rand(min_health, SSartifacts.heal_uncommon_maximum_health)
			if(ART_RARITY_RARE)
				num_damages = rand(1, SSartifacts.damage_max_types_rare)
				if(force_buff)
					max_health = SSartifacts.heal_rare_maximum_health
				else
					max_health = rand(min_health, SSartifacts.heal_rare_maximum_health)
	if(isnull(LAZYACCESS(overridden, ARTFLAG_DAMAGE_PRESET)))
		switch(rarity)
			if(ART_RARITY_COMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_common) // so, one
			if(ART_RARITY_UNCOMMON)
				num_damages = rand(1, SSartifacts.damage_max_types_uncommon)
			if(ART_RARITY_RARE)
				num_damages = rand(1, SSartifacts.damage_max_types_rare)
		for(var/i in 1 to num_damages)
			var/damtype = pick(alltypes)
			alltypes -= list(damtype)
			switch(damtype)
				if(BRUTE)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_brute = rand(SSartifacts.heal_dps_brute_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_brute = rand(SSartifacts.heal_dps_brute_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_brute = rand(SSartifacts.heal_dps_brute_rare_maximum, 0)
					d_brute = -abs(round(d_brute, SSartifacts.damage_discrete))
				if(BURN)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_burn = rand(SSartifacts.heal_dps_burn_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_burn = rand(SSartifacts.heal_dps_burn_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_burn = rand(SSartifacts.heal_dps_burn_rare_maximum, 0)
					d_burn = -abs(round(d_burn, SSartifacts.damage_discrete))
				if(TOX)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_toxin = rand(SSartifacts.heal_dps_toxin_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_toxin = rand(SSartifacts.heal_dps_toxin_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_toxin = rand(SSartifacts.heal_dps_toxin_rare_maximum, 0)
					d_toxin = -abs(round(d_toxin, SSartifacts.damage_discrete))
				if(OXY)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_oxy = rand(SSartifacts.heal_dps_oxy_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_oxy = rand(SSartifacts.heal_dps_oxy_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_oxy = rand(SSartifacts.heal_dps_oxy_rare_maximum, 0)
					d_oxy = -abs(round(d_oxy, SSartifacts.damage_discrete))
				if(CLONE)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_clone = rand(SSartifacts.heal_dps_clone_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_clone = rand(SSartifacts.heal_dps_clone_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_clone = rand(SSartifacts.heal_dps_clone_rare_maximum, 0)
					d_clone = -abs(round(d_clone, SSartifacts.damage_discrete))
				if(BRAIN)
					switch(rarity)
						if(ART_RARITY_COMMON)
							d_brain = rand(SSartifacts.heal_dps_brain_common_maximum, 0)
						if(ART_RARITY_UNCOMMON)
							d_brain = rand(SSartifacts.heal_dps_brain_uncommon_maximum, 0)
						if(ART_RARITY_RARE)
							d_brain = rand(SSartifacts.heal_dps_brain_rare_maximum, 0)
					d_brain = -abs(round(d_brain, SSartifacts.damage_discrete))
	//yeah its the same damn proc, whatcha gonna do about it?

/datum/artifact_effect/passive_damage/healer/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	if(target.health < min_health)
		return
	if(target.health > max_health)
		return
	var/mult = is_dps ? ((world.time - last_applied) * 0.1) : 1
	var/dr = 1
	var/dt = 0
	if(!implanted)
		dr = check_armor(target, armor_flag)
		dt = check_dt(target)
	if(implanted || !in_desired_slot())
		mult *= undesirable_mult
	if(d_brute)
		target.apply_damage(
			-abs(d_brute) * mult,
			BRUTE,
			blocked = dr,
			damage_threshold = dt,
			spread_damage = TRUE
		)
	if(d_burn)
		target.apply_damage(
			-abs(d_burn) * mult,
			BURN,
			blocked = dr,
			damage_threshold = dt,
			spread_damage = TRUE
		)
	if(d_toxin)
		target.apply_damage(
			-abs(d_toxin) * mult,
			TOX,
			blocked = dr,
			damage_threshold = dt,
			spread_damage = TRUE
		)
	if(d_oxy)
		target.apply_damage(
			-abs(d_oxy) * mult,
			OXY,
			blocked = dr,
			damage_threshold = dt,
			spread_damage = TRUE
		)
	if(d_clone)
		target.apply_damage(
			-abs(d_clone) * mult,
			CLONE,
			blocked = dr,
			damage_threshold = dt,
			spread_damage = TRUE
		)
	if(d_brain)
		target.adjustOrganLoss(ORGAN_SLOT_BRAIN, (((-abs(d_brain) * mult) - dt) * dr))

	last_applied = world.time
	//send_message(target, LAZYACCESS(dmg_out, 2))
	return TRUE

/datum/artifact_effect/passive_damage/healer/update_highest_damage()
	highest_damage = BRUTE
	if(abs(d_brute) < abs(d_burn))
		highest_damage = BURN
	if(abs(d_burn) < abs(d_toxin))
		highest_damage = TOX
	if(abs(d_toxin) < abs(d_oxy))
		highest_damage = OXY
	if(abs(d_oxy) < abs(d_clone))
		highest_damage = CLONE
	if(abs(d_clone) < abs(d_brain))
		highest_damage = BRAIN

/datum/artifact_effect/passive_damage/healer/get_magnitude(isprefix)
	var/possy = 1
	switch(highest_damage)
		if(BRUTE)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_brute) * (abs(d_brute) / SSartifacts.heal_dps_brute_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_brute) * (abs(d_brute) / SSartifacts.heal_dps_brute_rare_maximum), 1)
		if(BURN)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_burn) * (abs(d_burn) / SSartifacts.heal_dps_burn_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_burn) * (abs(d_burn) / SSartifacts.heal_dps_burn_rare_maximum), 1)
		if(TOX)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_toxin) * (abs(d_toxin) / SSartifacts.heal_dps_toxin_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_toxin) * (abs(d_toxin) / SSartifacts.heal_dps_toxin_rare_maximum), 1)
		if(OXY)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_oxy) * (abs(d_oxy) / SSartifacts.heal_dps_oxy_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_oxy) * (abs(d_oxy) / SSartifacts.heal_dps_oxy_rare_maximum), 1)
		if(CLONE)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_clone) * (abs(d_clone) / SSartifacts.heal_dps_clone_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_clone) * (abs(d_clone) / SSartifacts.heal_dps_clone_rare_maximum), 1)
		if(BRAIN)
			if(isprefix)
				possy = round(LAZYLEN(SSartifacts.prefixes_heal_brain) * (abs(d_brain) / SSartifacts.heal_dps_brain_rare_maximum), 1)
			else
				possy = round(LAZYLEN(SSartifacts.suffixes_heal_brain) * (abs(d_brain) / SSartifacts.heal_dps_brain_rare_maximum), 1)
	return possy

/datum/artifact_effect/passive_damage/healer/update_prefix()
	update_highest_damage()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	switch(highest_damage)
		if(BRUTE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_brute))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_brute, index)
		if(BURN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_burn))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_burn, index)
		if(TOX)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_toxin))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_toxin, index)
		if(OXY)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_oxy))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_oxy, index)
		if(CLONE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_clone))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_clone, index)
		if(BRAIN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.prefixes_heal_brain))
			prefix = LAZYACCESS(SSartifacts.prefixes_heal_brain, index)
	return prefix

/datum/artifact_effect/passive_damage/healer/update_suffix()
	update_highest_damage()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	switch(highest_damage)
		if(BRUTE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_brute))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_brute, index)
		if(BURN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_burn))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_burn, index)
		if(TOX)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_toxin))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_toxin, index)
		if(OXY)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_oxy))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_oxy, index)
		if(CLONE)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_clone))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_clone, index)
		if(BRAIN)
			index = clamp(index, 1, LAZYLEN(SSartifacts.suffixes_heal_brain))
			suffix = LAZYACCESS(SSartifacts.suffixes_heal_brain, index)
	return suffix

/datum/artifact_effect/passive_damage/healer/update_desc()
	var/list/out = list()
	var/the_min_health = clamp(min_health, -100, 200)
	var/the_max_health = clamp(max_health, -100, 200)
	if(d_brute)
		out += span_green("Heals [d_brute] brute damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	if(d_burn)
		out += span_green("Heals [d_burn] burn damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	if(d_toxin)
		out += span_green("Heals [d_toxin] toxin damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	if(d_oxy)
		out += span_green("Heals [d_oxy] oxy damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	if(d_clone)
		out += span_green("Heals [d_clone] clone damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	if(d_brain)
		out += span_green("Heals [d_brain] brain damage per second while the wearer is above [the_min_health] and below [the_max_health] when stored [desired_slots_string].")
	out += span_notice("Heals at [undesirable_mult]x the rate while stored anywhere else.")
	descriptions = out


///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// stamina ADJUSTER   ///
/// Can use for healing ///
/datum/artifact_effect/stamina
	kind = ARTMOD_STAMINA
	chance_weight = 4
	/// How much to adjust stamina by
	var/stamina_adjustment = 0
	/// Cooldown if it stamcrits the user
	var/stamcrit_cooldown = 20 SECONDS
	COOLDOWN_DECLARE(stamcritted)

/datum/artifact_effect/stamina/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_STAMINA_ADJUSTMENT)))
		stamina_adjustment = LAZYACCESS(parameters, ARTVAR_STAMINA_ADJUSTMENT)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_STAMCRIT_COOLDOWN)))
		stamcrit_cooldown = LAZYACCESS(parameters, ARTVAR_STAMCRIT_COOLDOWN)
	is_buff = (stamina_adjustment > 0)
	. = ..()

/datum/artifact_effect/stamina/randomize(rarity, force_buff)
	if(stamina_adjustment == initial(stamina_adjustment))
		switch(rarity)
			if(ART_RARITY_COMMON)
				stamina_adjustment = rand(SSartifacts.stamina_rate_common_minimum, force_buff ? 0 : SSartifacts.stamina_rate_common_maximum)
			if(ART_RARITY_UNCOMMON)
				stamina_adjustment = rand(SSartifacts.stamina_rate_uncommon_minimum, force_buff ? 0 : SSartifacts.stamina_rate_uncommon_maximum)
			if(ART_RARITY_RARE)
				stamina_adjustment = rand(SSartifacts.stamina_rate_rare_minimum, force_buff ? 0 : SSartifacts.stamina_rate_rare_maximum)
	stamina_adjustment = round(stamina_adjustment, SSartifacts.stamina_discrete)
	is_buff = (stamina_adjustment > 0)
	. = ..()

/datum/artifact_effect/stamina/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	if(!is_buff)
		if(stamcritted && !COOLDOWN_FINISHED(src, stamcritted))
			return
		if(IS_STAMCRIT(target))
			COOLDOWN_START(src, stamcritted, stamcrit_cooldown)
			return
	else
		if(!in_desired_slot())
			return
	target.adjustStaminaLossBuffered(stamina_adjustment)
	return TRUE

/datum/artifact_effect/stamina/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_stamina_good) * (abs(stamina_adjustment) / SSartifacts.stamina_rate_rare_minimum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_stamina_good) * (abs(stamina_adjustment) / SSartifacts.stamina_rate_rare_minimum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_stamina_bad) * (abs(stamina_adjustment) / abs(SSartifacts.stamina_rate_rare_maximum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_stamina_bad) * (abs(stamina_adjustment) / abs(SSartifacts.stamina_rate_rare_maximum)), 1)
	return possy

/datum/artifact_effect/stamina/update_prefix()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.prefixes_stamina_good) : LAZYLEN(SSartifacts.prefixes_stamina_bad))
	prefix = LAZYACCESS(is_buff ? SSartifacts.prefixes_stamina_good : SSartifacts.prefixes_stamina_bad, index)
	return prefix

/datum/artifact_effect/stamina/update_suffix()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.suffixes_stamina_good) : LAZYLEN(SSartifacts.suffixes_stamina_bad))
	suffix = LAZYACCESS(is_buff ? SSartifacts.suffixes_stamina_good : SSartifacts.suffixes_stamina_bad, index)
	return suffix

/datum/artifact_effect/stamina/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Replenishes your stamina by [abs(stamina_adjustment)] points per second when stored [desired_slots_string].")
	else
		out += span_alert("Depletes your stamina by [abs(stamina_adjustment)] points per second.")
	descriptions = out

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// RADIATION            ///
/// Can use for healing ///
/datum/artifact_effect/radiation
	kind = ARTMOD_RADIATION
	chance_weight = 10
	var/target_radiation = 0
	var/radiation_adjustment = 0

/datum/artifact_effect/radiation/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_RADIATION_ADJUSTMENT)))
		radiation_adjustment = LAZYACCESS(parameters, ARTVAR_RADIATION_ADJUSTMENT)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TARGET_RADIATION)))
		target_radiation = LAZYACCESS(parameters, ARTVAR_TARGET_RADIATION)
	is_buff = (target_radiation < RAD_MOB_SAFE)
	. = ..()

/datum/artifact_effect/radiation/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	var/mult = (world.time - last_applied) * 0.1
	if(is_buff && !in_desired_slot())
		return
	var/radz = target.radiation
	if(ISABOUTEQUAL(radz, target_radiation, radiation_adjustment * 5))
		return TRUE // already where we want it
	if(radz > target_radiation)
		target.radiation += (radiation_adjustment * mult)
	else
		target.rad_act(radiation_adjustment * mult, implanted)
	return TRUE

/datum/artifact_effect/radiation/randomize(rarity, force_buff)
	if(target_radiation == initial(target_radiation))
		switch(rarity)
			if(ART_RARITY_COMMON)
				target_radiation = (force_buff ? 0 : rand(0, SSartifacts.radiation_target_common_maximum))
			if(ART_RARITY_UNCOMMON)
				target_radiation = (force_buff ? 0 : rand(0, SSartifacts.radiation_target_uncommon_maximum))
			if(ART_RARITY_RARE)
				target_radiation = (force_buff ? 0 : rand(0, SSartifacts.radiation_target_rare_maximum))
	if(radiation_adjustment == initial(radiation_adjustment))
		radiation_adjustment = round(radiation_adjustment, SSartifacts.radiation_discrete)
	is_buff = (target_radiation < RAD_MOB_SAFE)
	. = ..()

/datum/artifact_effect/radiation/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_radiation_good) * (abs(radiation_adjustment) / SSartifacts.radiation_rate_rare_minimum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_radiation_good) * (abs(radiation_adjustment) / SSartifacts.radiation_rate_rare_minimum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_radiation_bad) * (abs(radiation_adjustment) / abs(SSartifacts.radiation_rate_rare_maximum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_radiation_bad) * (abs(radiation_adjustment) / abs(SSartifacts.radiation_rate_rare_maximum)), 1)
	return possy

/datum/artifact_effect/radiation/update_prefix()
	var/index = get_magnitude(TRUE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.prefixes_radiation_good) : LAZYLEN(SSartifacts.prefixes_radiation_bad))
	prefix = LAZYACCESS(is_buff ? SSartifacts.prefixes_radiation_good : SSartifacts.prefixes_radiation_bad, index)
	return prefix

/datum/artifact_effect/radiation/update_suffix()
	var/index = get_magnitude(FALSE)
	index += rand(0, 3)
	index = clamp(index, 1, is_buff ? LAZYLEN(SSartifacts.suffixes_radiation_good) : LAZYLEN(SSartifacts.suffixes_radiation_bad))
	suffix = LAZYACCESS(is_buff ? SSartifacts.suffixes_radiation_good : SSartifacts.suffixes_radiation_bad, index)
	return suffix

/datum/artifact_effect/radiation/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Increases/decreases your radiation to [target_radiation] rads at [abs(radiation_adjustment)] points per second when stored [desired_slots_string].")
	else
		out += span_alert("Increases/decreases your radiation to [target_radiation] rads at [abs(radiation_adjustment)] points per second.")
	descriptions = out


///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// BLOOD ADJUSTER               /// i just like to give my objects a big hairdo okay??
/// Trends blood toward a value ///
/datum/artifact_effect/blood
	kind = ARTMOD_BLOOD
	chance_weight = 2
	/// Target blood amount, if any
	var/target_blood = 0
	/// How much to adjust blood by per second
	var/blood_adjustment = 0

/datum/artifact_effect/blood/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_BLOOD_ADJUSTMENT)))
		blood_adjustment = LAZYACCESS(parameters, ARTVAR_BLOOD_ADJUSTMENT)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TARGET_BLOOD)))
		target_blood = LAZYACCESS(parameters, ARTVAR_TARGET_BLOOD)
	is_buff = (target_blood > BLOOD_VOLUME_SYMPTOMS_WARN)
	. = ..()

/datum/artifact_effect/blood/randomize(rarity, force_buff)
	if(target_blood == initial(target_blood))
		switch(rarity)
			if(ART_RARITY_COMMON)
				target_blood = (force_buff ? BLOOD_VOLUME_NORMAL : rand(SSartifacts.blood_target_common_minimum, BLOOD_VOLUME_NORMAL))
			if(ART_RARITY_UNCOMMON)
				target_blood = (force_buff ? BLOOD_VOLUME_NORMAL : rand(SSartifacts.blood_target_uncommon_minimum, BLOOD_VOLUME_NORMAL))
			if(ART_RARITY_RARE)
				target_blood = (force_buff ? BLOOD_VOLUME_NORMAL : rand(SSartifacts.blood_target_rare_minimum, BLOOD_VOLUME_NORMAL))
	if(blood_adjustment == initial(blood_adjustment))
		switch(rarity)
			if(ART_RARITY_COMMON)
				blood_adjustment = rand(0, SSartifacts.blood_rate_common_maximum)
			if(ART_RARITY_UNCOMMON)
				blood_adjustment = rand(0, SSartifacts.blood_rate_uncommon_maximum)
			if(ART_RARITY_RARE)
				blood_adjustment = rand(0, SSartifacts.blood_rate_rare_maximum)
	blood_adjustment = round(blood_adjustment, SSartifacts.blood_discrete)
	is_buff = (target_blood > BLOOD_VOLUME_SYMPTOMS_WARN)
	. = ..()

/datum/artifact_effect/blood/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	var/mult = (world.time - last_applied) * 0.1
	if(is_buff && !in_desired_slot())
		return
	var/bloodvol = target.get_blood(TRUE)
	if(ISABOUTEQUAL(bloodvol, target_blood, blood_adjustment * 2))
		return TRUE // already where we want it
	var/up_or_down = bloodvol < target_blood ? 1 : -1
	target.blood_volume += (blood_adjustment * mult * up_or_down)
	return TRUE

/datum/artifact_effect/blood/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_blood_good) * (abs(blood_adjustment) / SSartifacts.blood_rate_rare_maximum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_blood_good) * (abs(blood_adjustment) / SSartifacts.blood_rate_rare_maximum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_blood_bad) * (abs(blood_adjustment) / abs(SSartifacts.blood_rate_rare_maximum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_blood_bad) * (abs(blood_adjustment) / abs(SSartifacts.blood_rate_rare_maximum)), 1)
	return possy

/datum/artifact_effect/blood/update_suffix(is_buff, index)
	var/suffix = ""
	if(is_buff)
		suffix = LAZYACCESS(SSartifacts.suffixes_blood_good, index)
	else
		suffix = LAZYACCESS(SSartifacts.suffixes_blood_bad, index)
	return suffix

/datum/artifact_effect/blood/update_prefix(is_buff, index)
	var/prefix = ""
	if(is_buff)
		prefix = LAZYACCESS(SSartifacts.prefixes_blood_good, index)
	else
		prefix = LAZYACCESS(SSartifacts.prefixes_blood_bad, index)
	return prefix

/datum/artifact_effect/blood/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Increases/decreases your blood to [target_blood]u at [abs(blood_adjustment)] points per second when stored [desired_slots_string].")
	else
		out += span_alert("Increases/decreases your blood to [target_blood]u at [abs(blood_adjustment)] points per second.")
	descriptions = out

////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////
/// NUTRITION ADJUSTER                   ////////////
/// Trends nutrition toward a value     ////////////
/// toooootally isnt a fatten up thing ////////////
/datum/artifact_effect/feeder
	kind = ARTMOD_FEEDER
	chance_weight = 1
	/// Target nutrition amount, if any
	var/target_nutrition = 0
	/// How much to adjust nutrition by per second
	var/nutrition_adjustment = 0

/datum/artifact_effect/feeder/apply_parameters(list/parameters = list())
	if(!isnull(LAZYACCESS(parameters, ARTVAR_NUTRITION_ADJUSTMENT)))
		nutrition_adjustment = LAZYACCESS(parameters, ARTVAR_NUTRITION_ADJUSTMENT)
	if(!isnull(LAZYACCESS(parameters, ARTVAR_TARGET_NUTRITION)))
		target_nutrition = LAZYACCESS(parameters, ARTVAR_TARGET_NUTRITION)
	is_buff = (target_nutrition > NUTRITION_LEVEL_FED)
	. = ..()

/datum/artifact_effect/feeder/randomize(rarity, force_buff)
	if(target_nutrition == initial(target_nutrition))
		switch(rarity)
			if(ART_RARITY_COMMON)
				target_nutrition = (force_buff ? NUTRITION_LEVEL_FULL : rand(0, SSartifacts.nutrition_target_common_maximum))
			if(ART_RARITY_UNCOMMON)
				target_nutrition = (force_buff ? NUTRITION_LEVEL_FULL : rand(0, SSartifacts.nutrition_target_uncommon_maximum))
			if(ART_RARITY_RARE)
				target_nutrition = (force_buff ? NUTRITION_LEVEL_FULL : rand(0, SSartifacts.nutrition_target_rare_maximum))
	if(nutrition_adjustment == initial(nutrition_adjustment))
		switch(rarity)
			if(ART_RARITY_COMMON)
				nutrition_adjustment = rand(SSartifacts.nutrition_rate_common_minimum, SSartifacts.nutrition_rate_common_maximum)
			if(ART_RARITY_UNCOMMON)
				nutrition_adjustment = rand(SSartifacts.nutrition_rate_uncommon_minimum, SSartifacts.nutrition_rate_uncommon_maximum)
			if(ART_RARITY_RARE)
				nutrition_adjustment = rand(SSartifacts.nutrition_rate_rare_minimum, SSartifacts.nutrition_rate_rare_maximum)
	nutrition_adjustment = round(nutrition_adjustment, SSartifacts.nutrition_discrete)
	is_buff = (target_nutrition > NUTRITION_LEVEL_FED)
	. = ..()

/datum/artifact_effect/feeder/on_tick(obj/item/master, mob/living/target, obj/item/holder)
	if(!isliving(target))
		return
	var/mult = (world.time - last_applied) * 0.1
	var/nutritionvol = target.nutrition
	if(ISABOUTEQUAL(nutritionvol, target_nutrition, nutrition_adjustment * 2))
		return TRUE // already where we want it
	var/up_or_down = nutritionvol < target_nutrition ? 1 : -1
	target.adjust_nutrition(nutrition_adjustment * mult * up_or_down)
	return TRUE

/datum/artifact_effect/feeder/get_magnitude(isprefix)
	var/possy = 1
	if(is_buff)
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_nutrition_good) * (abs(nutrition_adjustment) / SSartifacts.nutrition_rate_rare_maximum), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_nutrition_good) * (abs(nutrition_adjustment) / SSartifacts.nutrition_rate_rare_maximum), 1)
	else
		if(isprefix)
			possy = round(LAZYLEN(SSartifacts.prefixes_nutrition_bad) * (abs(nutrition_adjustment) / abs(SSartifacts.nutrition_rate_rare_maximum)), 1)
		else
			possy = round(LAZYLEN(SSartifacts.suffixes_nutrition_bad) * (abs(nutrition_adjustment) / abs(SSartifacts.nutrition_rate_rare_maximum)), 1)
	return possy

/datum/artifact_effect/feeder/update_suffix(is_buff, index)
	var/suffix = ""
	if(is_buff)
		suffix = LAZYACCESS(SSartifacts.suffixes_nutrition_good, index)
	else
		suffix = LAZYACCESS(SSartifacts.suffixes_nutrition_bad, index)
	return suffix

/datum/artifact_effect/feeder/update_prefix(is_buff, index)
	var/prefix = ""
	if(is_buff)
		prefix = LAZYACCESS(SSartifacts.prefixes_nutrition_good, index)
	else
		prefix = LAZYACCESS(SSartifacts.prefixes_nutrition_bad, index)
	return prefix

/datum/artifact_effect/blood/update_desc()
	var/list/out = list()
	if(is_buff)
		out += span_green("Passively feeds you.")
	else
		out += span_alert("Rapidly digests anything eaten.")
	descriptions = out

///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////
/// BLEEDING ADJUSTER           ///
/// coming soon!				///

/// Also coming soon:
/// melee damage
/// recoil / accuracy




