const dateFormatter = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" });
const moneyFormatter = new Intl.NumberFormat("en-GH", { style: "currency", currency: "GHS", maximumFractionDigits: 0 });

export function formatDate(value) {
  return value ? dateFormatter.format(new Date(value)) : "—";
}

export function formatDay(isoDate) {
  return isoDate ? formatDate(`${isoDate}T12:00:00`) : "—";
}

export function formatMoney(amount) {
  return moneyFormatter.format(amount);
}

export function localIsoDate(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function setMessageText(element, text) {
  element.textContent = text;
  element.hidden = !text;
}

export function renderEmptyRow(tbody, colspan, text) {
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = colspan;
  cell.className = "admin__table-empty";
  cell.textContent = text;
  row.append(cell);
  tbody.replaceChildren(row);
}

export function createRow(cells, labels = []) {
  const row = document.createElement("tr");
  cells.forEach((text, index) => {
    const cell = document.createElement("td");
    cell.textContent = text;
    if (labels[index]) cell.dataset.label = labels[index];
    row.append(cell);
  });
  return row;
}

export function createActionCell(...buttons) {
  const cell = document.createElement("td");
  cell.className = "admin__table-actions";
  cell.append(...buttons.filter(Boolean));
  return cell;
}

export function createTableButton(label, className, dataset) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.textContent = label;
  Object.assign(button.dataset, dataset);
  return button;
}
