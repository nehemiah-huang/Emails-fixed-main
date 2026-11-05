import { supabase } from "./supabase-client.js";
import { createActionCell, createTableButton, formatDay, localIsoDate, renderEmptyRow, createRow, setMessageText } from "./admin-table.js";
import { IMAGE_ACCEPT, uploadSiteImage } from "./admin-upload.js";

const BLOCK_LIMIT = 100;
const FOREIGN_KEY_VIOLATION = "23503";

const roomsBody = document.getElementById("roomsBody");
const roomForm = document.getElementById("roomForm");
const roomName = document.getElementById("roomName");
const roomError = document.getElementById("roomError");
const roomPhoto = document.getElementById("roomPhoto");
const roomPhotoInput = document.getElementById("roomPhotoInput");
roomPhoto.accept = IMAGE_ACCEPT;
const blockForm = document.getElementById("blockForm");
const blockRoom = document.getElementById("blockRoom");
const blockStart = document.getElementById("blockStart");
const blockEnd = document.getElementById("blockEnd");
const blockReason = document.getElementById("blockReason");
const blockError = document.getElementById("blockError");
const blockSubmit = document.getElementById("blockSubmit");
const blocksBody = document.getElementById("blocksBody");

export async function fetchRooms() {
  const { data, error } = await supabase
    .from("stay_rooms")
    .select("id, name, is_active, image_path")
    .order("name");

  if (error) throw error;
  return data;
}

function fillRoomOptions(rooms) {
  blockRoom.replaceChildren(...rooms.map(room => {
    const option = document.createElement("option");
    option.value = room.id;
    option.textContent = room.is_active ? room.name : `${room.name} (closed)`;
    return option;
  }));
}

function renderPhotoCell(room) {
  const cell = document.createElement("td");
  cell.dataset.label = "Photo";

  if (room.image_path) {
    const image = document.createElement("img");
    image.className = "admin__room-thumb";
    image.src = room.image_path;
    image.alt = room.name;
    image.loading = "lazy";
    cell.append(image);
  } else {
    cell.textContent = "No photo";
  }

  return cell;
}

function renderRoomRow(room) {
  const row = createRow([room.name, room.is_active ? "Open for bookings" : "Closed"], ["Room", "Status"]);

  row.append(renderPhotoCell(room));
  const toggleButton = createTableButton(
    room.is_active ? "Close room" : "Reopen room",
    "admin__button admin__button--small",
    { roomId: room.id, nextActive: String(!room.is_active) }
  );
  const deleteButton = createTableButton(
    "Delete",
    "admin__button admin__button--small admin__button--danger",
    { deleteRoomId: room.id, roomName: room.name }
  );

  const photoButton = createTableButton(
    room.image_path ? "Change photo" : "Add photo",
    "admin__button admin__button--small",
    { roomPhotoId: room.id }
  );
  row.append(createActionCell(toggleButton, photoButton, deleteButton));
  return row;
}

async function loadRooms() {
  const rooms = await fetchRooms();

  if (!rooms.length) {
    renderEmptyRow(roomsBody, 4, "No rooms yet. Add each room's name below.");
    blockRoom.replaceChildren();
    return;
  }

  roomsBody.replaceChildren(...rooms.map(renderRoomRow));
  fillRoomOptions(rooms);
}

function renderBlockRow(block) {
  const row = createRow([
    block.stay_rooms?.name ?? "—",
    `${formatDay(block.starts_on)} to ${formatDay(block.ends_on)}`,
    block.reason || "—"
  ], ["Room", "Dates", "Reason"]);

  const button = createTableButton(
    "Delete",
    "admin__button admin__button--small admin__button--danger",
    { blockId: block.id }
  );

  row.append(createActionCell(button));
  return row;
}

async function loadBlocks() {
  const { data, error } = await supabase
    .from("stay_room_blocks")
    .select("id, starts_on, ends_on, reason, stay_rooms(name)")
    .gte("ends_on", localIsoDate())
    .order("starts_on")
    .limit(BLOCK_LIMIT);

  if (error) throw error;

  if (!data.length) {
    renderEmptyRow(blocksBody, 4, "No upcoming blocked dates.");
    return;
  }

  blocksBody.replaceChildren(...data.map(renderBlockRow));
}

export async function loadAvailability() {
  await Promise.all([loadRooms(), loadBlocks()]);
}

roomForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setMessageText(roomError, "");

  const name = roomName.value.trim();

  if (!name) {
    setMessageText(roomError, "Enter a name for the room.");
    return;
  }

  let imagePath = "";
  const photo = roomPhoto.files[0];
  if (photo) {
    try {
      imagePath = await uploadSiteImage(photo);
    } catch (uploadError) {
      setMessageText(roomError, "The photo could not be uploaded. Please try again.");
      return;
    }
  }

  const { error } = await supabase.from("stay_rooms").insert({ name, image_path: imagePath });

  if (error) {
    setMessageText(
      roomError,
      error.code === "23505" ? "A room with that name already exists." : "The room could not be added. Please try again."
    );
    return;
  }

  roomForm.reset();
  await loadRooms();
});

roomsBody.addEventListener("click", async (event) => {
  const photoButton = event.target.closest("button[data-room-photo-id]");
  if (photoButton) {
    roomPhotoInput.dataset.roomId = photoButton.dataset.roomPhotoId;
    roomPhotoInput.click();
    return;
  }

  const deleteButton = event.target.closest("button[data-delete-room-id]");

  if (deleteButton) {
    await deleteRoom(deleteButton);
    return;
  }

  const button = event.target.closest("button[data-room-id]");
  if (!button) return;

  button.disabled = true;
  setMessageText(roomError, "");

  const { error } = await supabase
    .from("stay_rooms")
    .update({ is_active: button.dataset.nextActive === "true" })
    .eq("id", button.dataset.roomId);

  if (error) {
    setMessageText(roomError, "The room status could not be changed. Please try again.");
    button.disabled = false;
    return;
  }

  await loadRooms();
});

async function deleteRoom(button) {
  if (!window.confirm(`Delete the room "${button.dataset.roomName}"? Its blocked dates will be removed too.`)) return;

  button.disabled = true;
  setMessageText(roomError, "");

  const { data, error } = await supabase
    .from("stay_rooms")
    .delete()
    .eq("id", button.dataset.deleteRoomId)
    .select("id");

  if (error) {
    setMessageText(
      roomError,
      error.code === FOREIGN_KEY_VIOLATION
        ? "This room has bookings, so it cannot be deleted. Close it instead."
        : "This room could not be deleted. Please try again."
    );
    button.disabled = false;
    return;
  }

  if (!data.length) {
    setMessageText(roomError, "That room could not be deleted.");
    button.disabled = false;
    return;
  }

  await loadRooms();
  await loadBlocks();
}

roomPhotoInput.addEventListener("change", async () => {
  const file = roomPhotoInput.files[0];
  const roomId = roomPhotoInput.dataset.roomId;
  roomPhotoInput.value = "";
  if (!file) return;

  setMessageText(roomError, "");

  try {
    const imagePath = await uploadSiteImage(file);
    const { data, error } = await supabase
      .from("stay_rooms")
      .update({ image_path: imagePath })
      .eq("id", roomId)
      .select("id");

    if (error || !data.length) {
      console.error("Room photo save failed:", error);
      setMessageText(roomError, "The photo could not be saved. Please try again.");
      return;
    }
  } catch (uploadError) {
    setMessageText(roomError, "The photo could not be uploaded. Please try again.");
    return;
  }

  await loadRooms();
});

blockForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setMessageText(blockError, "");

  if (!blockStart.value || !blockEnd.value || blockEnd.value <= blockStart.value) {
    setMessageText(blockError, "The end date must be after the start date.");
    return;
  }

  blockSubmit.disabled = true;

  const { error } = await supabase.rpc("admin_block_room", {
    p_room_id: blockRoom.value,
    p_starts_on: blockStart.value,
    p_ends_on: blockEnd.value,
    p_reason: blockReason.value
  });

  blockSubmit.disabled = false;

  if (error) {
    setMessageText(blockError, "Those dates could not be blocked. Please check the dates and try again.");
    return;
  }

  blockForm.reset();
  await loadBlocks();
});

blocksBody.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-block-id]");
  if (!button) return;

  if (!window.confirm("Delete this blocked period? The room will be open for bookings on these dates.")) return;

  button.disabled = true;

  const { data, error } = await supabase
    .from("stay_room_blocks")
    .delete()
    .eq("id", button.dataset.blockId)
    .select("id");

  if (error || !data.length) {
    setMessageText(blockError, "That blocked period could not be deleted. Please try again.");
    button.disabled = false;
    return;
  }

  await loadBlocks();
});
