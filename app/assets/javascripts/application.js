//= require popper
//= require bootstrap 
//= require jquery

document.querySelectorAll('.clickable-row').forEach(row => {
  row.style.cursor = 'pointer';
});

document.addEventListener('DOMContentLoaded', function () {
  const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]');
  [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl));
});