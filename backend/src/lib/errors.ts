export class CivicError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(code: string, message: string, statusCode = 400) {
    super(message);
    this.name = "CivicError";
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class AddressNotFoundError extends CivicError {
  constructor(address: string) {
    super("address_not_found", `Could not verify address: ${address}`, 422);
  }
}

export class AddressOutsidePhiladelphiaError extends CivicError {
  constructor() {
    super(
      "address_outside_philadelphia",
      "Verified address is outside Philadelphia; v1 only supports Philly addresses.",
      422,
    );
  }
}

export class NoOfficialForDistrictError extends CivicError {
  constructor(district: string) {
    super(
      "no_official_for_district",
      `No filing official mapped for district ${district}.`,
      422,
    );
  }
}
