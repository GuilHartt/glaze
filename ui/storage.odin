package ui

// StorageKey identifies one stored value: the element it belongs to and its type. One element
// keeps as many values as it needs, as long as their types differ.
@(private)
StorageKey :: struct {
	id:   ElementId,
	type: typeid,
}

// StorageEntry is one stored value: its key, the value, what frees whatever the value owns, and
// the frame that last touched it.
@(private)
StorageEntry :: struct {
	key:     StorageKey,
	value:   rawptr,
	destroy: DestroyProc,
	frame:   u32,
}

// StorageTable is the open-addressed table the values live in. A slot with a zero id is empty, the
// table is a power of two wide and stays below half full, and `sweep` is where the purge stopped.
@(private)
StorageTable :: struct {
	slots: [dynamic]StorageEntry,
	used:  int,
	sweep: int,
}

// DestroyProc frees what one stored value owns, before the table frees the value itself. A value
// that owns memory passes one to Storage, so nothing dies with it.
DestroyProc :: #type proc(Value: rawptr)

// storage_hash folds `Key` into a slot index inside `mask`.
@(private="file")
storage_hash :: #force_inline proc "contextless" (Key: StorageKey, mask: u32) -> u32 {
	address := uintptr(type_info_of(Key.type))
	h := u32(address) ~ u32(address >> 32)
	h ~= u32(Key.id) * 0x9E3779B1
	h ~= h >> 16
	h *= 0x7feb352d
	h ~= h >> 15
	return h & mask
}

// storage_alive reports whether an entry was touched in the current or the previous frame, which is
// the window the purge keeps: the input phase of a frame still reads the previous frame's offsets.
@(private="file")
storage_alive :: #force_inline proc "contextless" (Entry: StorageEntry, Frame: u32) -> bool {
	return Entry.frame + 1 >= Frame
}

// storage_find returns the slot holding `Key`, or the empty slot where `Key` belongs, and reports
// which of the two it is.
@(private="file")
storage_find :: proc(Key: StorageKey) -> (index: int, found: bool) #no_bounds_check {
	slots := state.storage.slots
	if len(slots) == 0 do return -1, false

	mask := u32(len(slots) - 1)
	for i := storage_hash(Key, mask);; i = (i + 1) & mask {
		entry := &slots[i]
		if entry.key.id == 0 do return int(i), false
		if entry.key == Key do return int(i), true
	}
}

// storage_grow doubles the table and reinserts the live entries, freeing the dead ones it meets on
// the way, so growth never pays for entries the sweep has not reached yet.
@(private="file")
storage_grow :: proc() {
	old := state.storage.slots
	size := 8 if len(old) == 0 else len(old) * 2
	slots := make([dynamic]StorageEntry, size)
	mask := u32(size - 1)

	used := 0
	for &entry in old {
		if entry.key.id == 0 do continue
		if !storage_alive(entry, state.frame) {
			storage_free(&entry)
			continue
		}

		i := storage_hash(entry.key, mask)
		for slots[i].key.id != 0 do i = (i + 1) & mask
		slots[i] = entry
		used += 1
	}

	if len(old) > 0 do delete(old)
	state.storage.slots = slots
	state.storage.used = used
	state.storage.sweep = 0
}

// storage_free gives back one entry's value and everything the value owns.
@(private="file")
storage_free :: proc(Entry: ^StorageEntry) {
	if Entry.destroy != nil do Entry.destroy(Entry.value)
	free(Entry.value)
}

// storage_remove clears the slot at `Index` and pulls the entries behind it into the hole, so the
// probe chains stay whole. The shift is what lets the table drop an entry without tombstones.
@(private="file")
storage_remove :: proc(Index: int) #no_bounds_check {
	slots := state.storage.slots
	mask := u32(len(slots) - 1)

	hole := u32(Index)
	for {
		next := hole
		home: u32
		for {
			next = (next + 1) & mask
			if slots[next].key.id == 0 {
				slots[hole] = {}
				return
			}

			// The entry at `next` can fill `hole` only when its home is not in (hole, next].
			home = storage_hash(slots[next].key, mask)
			if next > hole {
				if hole < home && home <= next do continue
			} else {
				if hole < home || home <= next do continue
			}
			break
		}
		slots[hole] = slots[next]
		hole = next
	}
}

// storage_purge drops the dead entries the sweep reaches inside this frame's budget, resuming where
// it stopped, so the whole table is visited every few frames at a fixed cost.
@(private)
storage_purge :: proc() {
	// The sweep visits at most this many slots per frame.
	BUDGET :: 64

	table := &state.storage
	slots := table.slots
	if len(slots) == 0 do return

	end := min(table.sweep + BUDGET, len(slots))
	for i := table.sweep; i < end; i += 1 {
		entry := &slots[i]
		if entry.key.id == 0 || storage_alive(entry^, state.frame) do continue

		storage_free(entry)
		table.used -= 1
		storage_remove(i)

		// The removal pulled the entries behind into this slot, so look at it again.
		i -= 1
	}
	table.sweep = end if end < len(slots) else 0
}

// Storage returns the `T` stored under `Element`, allocating a zero value the first time that id
// asks for that type, and one element holds as many types as it needs. An entry untouched for a
// whole frame is dead: Storage starts it over fresh, and the sweep frees the ones nothing asks for.
Storage :: proc(Element: ElementId, $T: typeid, Destroy: DestroyProc = nil) -> ^T {
	key := StorageKey{id = Element, type = T}

	index, found := storage_find(key)
	if found {
		entry := &state.storage.slots[index]
		if storage_alive(entry^, state.frame) {
			entry.frame = state.frame
			return (^T)(entry.value)
		}

		storage_free(entry)
		entry^ = StorageEntry{key = key, value = new(T), destroy = Destroy, frame = state.frame}
		return (^T)(entry.value)
	}

	if index < 0 || state.storage.used * 2 >= len(state.storage.slots) {
		storage_grow()
		index, _ = storage_find(key)
	}

	ptr := new(T)
	state.storage.slots[index] = StorageEntry{key = key, value = ptr, destroy = Destroy, frame = state.frame}
	state.storage.used += 1
	return ptr
}
