from app.schemas.reference import ContractItem, SiteItem, ZoneItem


class ReferenceService:
    def __init__(self) -> None:
        self._sites = [
            SiteItem(id="la-valette", name="La Valette"),
            SiteItem(id="bastide", name="La Bastide"),
        ]

        self._contracts = [
            ContractItem(id="exploitation", name="Exploitation"),
            ContractItem(id="maintenance", name="Maintenance"),
        ]

        self._zones = [
            ZoneItem(
                id="boue-la-valette-exploitation",
                site_id="la-valette",
                contract_id="exploitation",
                name="Boue",
            ),
            ZoneItem(
                id="entree-la-valette-exploitation",
                site_id="la-valette",
                contract_id="exploitation",
                name="Entree des eaux",
            ),
            ZoneItem(
                id="eaux-traitees-la-valette-maintenance",
                site_id="la-valette",
                contract_id="maintenance",
                name="Eaux traitees",
            ),
            ZoneItem(
                id="bassin-bastide-maintenance",
                site_id="bastide",
                contract_id="maintenance",
                name="Bassin principal",
            ),
        ]

    def list_sites(self) -> list[SiteItem]:
        return self._sites

    def list_contracts(self) -> list[ContractItem]:
        return self._contracts

    def list_zones(
        self,
        site_id: str | None = None,
        contract_id: str | None = None,
    ) -> list[ZoneItem]:
        zones = self._zones
        if site_id:
            zones = [zone for zone in zones if zone.site_id == site_id]
        if contract_id:
            zones = [zone for zone in zones if zone.contract_id == contract_id]
        return zones


reference_service = ReferenceService()
