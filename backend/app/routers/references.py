from fastapi import APIRouter, Depends, Query

from app.dependencies import get_current_user
from app.schemas.reference import ContractItem, SiteItem, ZoneItem
from app.services.reference_service import reference_service


router = APIRouter(prefix="/references", tags=["references"])


@router.get("/sites", response_model=list[SiteItem])
def list_sites(_: dict[str, str] = Depends(get_current_user)) -> list[SiteItem]:
    return reference_service.list_sites()


@router.get("/contracts", response_model=list[ContractItem])
def list_contracts(_: dict[str, str] = Depends(get_current_user)) -> list[ContractItem]:
    return reference_service.list_contracts()


@router.get("/zones", response_model=list[ZoneItem])
def list_zones(
    site_id: str | None = Query(default=None),
    contract_id: str | None = Query(default=None),
    _: dict[str, str] = Depends(get_current_user),
) -> list[ZoneItem]:
    return reference_service.list_zones(site_id=site_id, contract_id=contract_id)
