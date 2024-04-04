#define CLIMB_DELAY_SHORT 0.2 SECONDS
#define CLIMB_DELAY_MEDIUM 1 SECONDS
#define CLIMB_DELAY_LONG 2 SECONDS

/obj/structure
	icon = 'icons/obj/structures/structures.dmi'
	var/climbable
	var/climb_delay = CLIMB_DELAY_LONG
	var/breakable
	var/list/debris
	var/unslashable = FALSE
	var/wrenchable = FALSE
	var/climb_layer //If it has a "climb" layer that the mob has to be over to look right climbing. Mostly for platforms.
	health = 100
	anchored = TRUE
	projectile_coverage = PROJECTILE_COVERAGE_MEDIUM
	can_block_movement = TRUE

/obj/structure/Initialize(mapload, ...)
	. = ..()
	if(climbable)
		verbs += /obj/structure/proc/climb_on

/obj/structure/Destroy()
	//before ..() because the parent does loc = null
	for(var/atom/movable/A in contents_recursive())
		var/obj/O = A
		if(!istype(O))
			continue
		if(O.unacidable)
			O.forceMove(get_turf(loc))
	debris = null
	. = ..()

/obj/structure/attack_animal(mob/living/user)
	if(breakable)
		if(user.wall_smash)
			visible_message(SPAN_DANGER("[user] smashes [src] apart!"))
			deconstruct(FALSE)

/obj/structure/attackby(obj/item/W, mob/user)
	if(HAS_TRAIT(W, TRAIT_TOOL_WRENCH))
		if(user.action_busy)
			return TRUE
		toggle_anchored(W, user)
		return TRUE
	..()

/obj/structure/ex_act(severity, direction)
	if(indestructible)
		return

	if(src.health) //Prevents unbreakable objects from being destroyed
		src.health -= severity
		if(src.health <= 0)
			handle_debris(severity, direction)
			deconstruct(FALSE)

/obj/structure/proc/handle_debris(severity = 0, direction = 0)
	if(!LAZYLEN(debris))
		return
	switch(severity)
		if(0)
			for(var/thing in debris)
				new thing(loc)
		if(0 to EXPLOSION_THRESHOLD_HIGH) //beyond EXPLOSION_THRESHOLD_HIGH, the explosion is too powerful to create debris. It's all atomized.
			for(var/thing in debris)
				var/obj/item/I = new thing(loc)
				I.explosion_throw(severity, direction)

/obj/structure/proc/climb_on()

	set name = "Climb structure"
	set desc = "Climbs onto a structure."
	set category = "Object"
	set src in oview(1)

	do_climb(usr)

/obj/structure/MouseDrop_T(mob/target, mob/user)
	. = ..()
	var/mob/living/H = user
	if(!istype(H) || target != user) //No making other people climb onto tables.
		return

	do_climb(target)

/obj/structure/proc/can_climb(mob/living/user)
	if(!climbable || !can_touch(user))
		return FALSE

	var/turf/T = get_turf(src)
	if(flags_atom & ON_BORDER)
		T = get_step(get_turf(src), dir)
		if(user.loc == T)
			T = get_turf(src)

	var/turf/U = get_turf(user)
	if(!istype(T) || !istype(U))
		return FALSE

	user.add_temp_pass_flags(PASS_MOB_THRU|PASS_OVER_THROW_MOB)
	var/atom/blocker = LinkBlocked(user, U, T, list(src))
	user.remove_temp_pass_flags(PASS_MOB_THRU|PASS_OVER_THROW_MOB)

	if(blocker)
		to_chat(user, SPAN_WARNING("\The [blocker] prevents you from climbing [src]."))
		return FALSE

	return TRUE

/obj/structure/proc/do_climb(mob/living/user, mods)
	if(!can_climb(user))
		return

	var/list/climbdata = list("climb_delay" = climb_delay)
	SEND_SIGNAL(user, COMSIG_LIVING_CLIMB_STRUCTURE, climbdata)
	var/final_climb_delay = climbdata["climb_delay"] //so it doesn't set structure's climb_delay to permanently be modified

	var/climb_over_string = final_climb_delay < 1 SECONDS ? "vaulting over" : "climbing onto"
	user.visible_message(SPAN_WARNING("[user] starts [flags_atom & ON_BORDER ? "leaping over" : climb_over_string] \the [src]!"))

	if(!do_after(user, final_climb_delay, INTERRUPT_NO_NEEDHAND, BUSY_ICON_GENERIC, numticks = 2))
		return

	if(!can_climb(user))
		return

	var/turf/TT = get_turf(src)
	if(flags_atom & ON_BORDER)
		TT = get_step(get_turf(src), dir)
		if(user.loc == TT)
			TT = get_turf(src)

	var/climb_string = final_climb_delay < 1 SECONDS ? "[user] vaults over \the [src]!" : "[user] climbs onto \the [src]!"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(skillcheck(H, SKILL_ENDURANCE, SKILL_ENDURANCE_MASTER))
			climb_string = "[user] tactically vaults over \the [src]!"
	user.visible_message(SPAN_WARNING(climb_string))

	var/list/grabbed_things = list()
	//var/original_layer
	for(var/obj/item/grab/grabbing in list(user.l_hand, user.r_hand))
		grabbed_things += grabbing.grabbed_thing
		/*
		Safety in case our layer doesn't reset in time. Not entirely safe, but with a short reset timer, it should be okay. But you never know.
		Can also cause issues if we're somehow in a logic fail of going from one thing to another thing with a higher climb_layer. Hopefully never comes up.
		Xeno large sprites are still entirely cursed when it comes to layering so I am not going to bother trying to fix that. Vehicles too, unfortunately.
		*/
		if(climb_layer && climb_layer > grabbing.grabbed_thing.layer)
			addtimer(VARSET_CALLBACK(grabbing.grabbed_thing, layer, grabbing.grabbed_thing.layer), 0.3 SECONDS)
			grabbing.grabbed_thing.layer = climb_layer

		grabbing.grabbed_thing.forceMove(user.loc)
	if(climb_layer && climb_layer > user.layer)
		addtimer(VARSET_CALLBACK(user, layer, user.layer), 0.3 SECONDS)
		user.layer = climb_layer
	user.forceMove(TT)

	for(var/atom/movable/thing as anything in grabbed_things) // grabbed things aren't moved to the tile immediately to: make the animation better, preserve the grab
		thing.forceMove(TT)

/obj/structure/proc/structure_shaken()

	for(var/mob/living/M in get_turf(src))

		if(HAS_TRAIT(M, TRAIT_FLOORED))
			return //No spamming this on people.

		M.apply_effect(5, WEAKEN)
		to_chat(M, SPAN_WARNING("You topple as \the [src] moves under you!"))

		if(prob(25))

			var/damage = rand(15,30)
			var/mob/living/carbon/human/H = M
			if(!istype(H))
				to_chat(H, SPAN_DANGER("You land heavily!"))
				M.apply_damage(damage, BRUTE)
				return

			var/obj/limb/affecting

			switch(pick(list("ankle","wrist","head","knee","elbow")))
				if("ankle")
					affecting = H.get_limb(pick("l_foot", "r_foot"))
				if("knee")
					affecting = H.get_limb(pick("l_leg", "r_leg"))
				if("wrist")
					affecting = H.get_limb(pick("l_hand", "r_hand"))
				if("elbow")
					affecting = H.get_limb(pick("l_arm", "r_arm"))
				if("head")
					affecting = H.get_limb("head")

			if(affecting)
				to_chat(M, SPAN_DANGER("You land heavily on your [affecting.display_name]!"))
				affecting.take_damage(damage, 0)
				if(affecting.parent)
					affecting.parent.add_autopsy_data("Misadventure", damage)
			else
				to_chat(H, SPAN_DANGER("You land heavily!"))
				H.apply_damage(damage, BRUTE)

			H.UpdateDamageIcon()
			H.updatehealth()
	return

/obj/structure/proc/can_touch(mob/living/user)
	if(!user)
		return 0
	if(!Adjacent(user) || !isturf(user.loc))
		return 0
	if(user.is_mob_restrained() || user.buckled)
		to_chat(user, SPAN_NOTICE("You need your hands and legs free for this."))
		return 0
	if(user.is_mob_incapacitated(TRUE) || user.body_position == LYING_DOWN)
		return 0
	if(isRemoteControlling(user))
		to_chat(user, SPAN_NOTICE("You need hands for this."))
		return 0
	return 1

/obj/structure/proc/toggle_anchored(obj/item/W, mob/user)
	if(!wrenchable)
		to_chat(user, SPAN_WARNING("The [src] cannot be [anchored ? "un" : ""]anchored."))
		return FALSE
	else
		// Wrenching is faster if we are better at engineering
		var/timer = max(10, 40 - user.skills.get_skill_level(SKILL_ENGINEER) * 10)
		if(do_after(usr, timer, INTERRUPT_ALL, BUSY_ICON_BUILD))
			anchored = !anchored
			playsound(loc, 'sound/items/Ratchet.ogg', 25, 1)
			if(anchored)
				user.visible_message(SPAN_NOTICE("[user] anchors [src] into place."),SPAN_NOTICE("You anchor [src] into place."))
			else
				user.visible_message(SPAN_NOTICE("[user] unanchors [src]."),SPAN_NOTICE("You unanchor [src]."))
			return TRUE

/obj/structure/get_applying_acid_time()
	if(unacidable)
		return -1

	return 4 SECONDS

//For the GM xeno-spawn submenu, so aliens can animate popping out of these if needed.

/obj/structure/proc/animate_crawl_reset()
	animate(src, pixel_x = initial(pixel_x), pixel_y = initial(pixel_y), easing = JUMP_EASING)

/obj/structure/proc/animate_crawl(speed = 3, loop_amount = -1, sections = 4)
	animate(src, pixel_x = rand(pixel_x-2,pixel_x+2), pixel_y = rand(pixel_y-2,pixel_y+2), time = speed, loop = loop_amount, easing = JUMP_EASING)
	for(var/i in 1 to sections)
		animate(pixel_x = rand(pixel_x-2,pixel_x+2), pixel_y = rand(pixel_y-2,pixel_y+2), time = speed, easing = JUMP_EASING)
