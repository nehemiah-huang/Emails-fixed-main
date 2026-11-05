const dateFormat = new Intl.DateTimeFormat("en-GH", {
  day: "numeric",
  month: "long",
  year: "numeric"
});

const ghsFormat = new Intl.NumberFormat("en-GH", {
  style: "currency",
  currency: "GHS",
  maximumFractionDigits: 0
});

const preciseGhsFormat = new Intl.NumberFormat("en-GH", {
  style: "currency",
  currency: "GHS",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

export function formatStayDate(isoDate) {
  return dateFormat.format(new Date(`${isoDate}T12:00:00`));
}

export function formatGhs(amount) {
  return ghsFormat.format(amount);
}

export function formatGhsPrecise(amount) {
  return preciseGhsFormat.format(amount);
}
