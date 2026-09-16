// Menghitung total harga booking. Logikanya SENGAJA berbeda per pricing_type
// karena aturan tiap kategori paket memang beda (lihat instruksi V3):
//
// - 'per_person'  (Student Package): total = base_price x jumlah orang.
// - 'fixed'        (paket lain): total = base_price, ditambah biaya orang tambahan
//                   HANYA jika paket itu punya additional_person_fee, dihitung dari
//                   orang ke-(included_people + 1) dan seterusnya.
//
// Kalau sebuah paket tidak punya additional_person_fee DAN punya max_people, jumlah
// orang tidak boleh melebihi max_people (mis. Maternity maks 3 orang, tidak ada opsi
// tambah bayar). Kalau tidak ada max_people ataupun additional_person_fee sama sekali,
// jumlah orang tidak dibatasi (paket yang datanya memang tidak menyebutkan aturan ini).
function computePricing(pkg, peopleCount) {
  const errors = [];
  const n = Number(peopleCount);

  if (!n || n < 1) {
    errors.push('Jumlah orang wajib diisi.');
    return { errors };
  }

  if (pkg.min_people && n < pkg.min_people) {
    errors.push(`${pkg.name} minimal ${pkg.min_people} orang.`);
    return { errors };
  }

  if (pkg.pricing_type === 'per_person') {
    return {
      errors: [],
      basePrice: pkg.base_price,
      additionalPeopleCharged: 0,
      additionalFeeTotal: 0,
      totalPrice: pkg.base_price * n
    };
  }

  // pricing_type === 'fixed'
  if (pkg.max_people && !pkg.additional_person_fee && n > pkg.max_people) {
    errors.push(`${pkg.name} maksimal ${pkg.max_people} orang.`);
    return { errors };
  }

  const included = pkg.included_people ?? pkg.max_people ?? n;
  const extraPeople = pkg.additional_person_fee ? Math.max(0, n - included) : 0;
  const additionalFeeTotal = extraPeople * (pkg.additional_person_fee || 0);

  return {
    errors: [],
    basePrice: pkg.base_price,
    additionalPeopleCharged: extraPeople,
    additionalFeeTotal,
    totalPrice: pkg.base_price + additionalFeeTotal
  };
}

module.exports = { computePricing };
