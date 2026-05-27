from pydantic import BaseModel


class SiteItem(BaseModel):
    id: str
    name: str


class ContractItem(BaseModel):
    id: str
    name: str


class ZoneItem(BaseModel):
    id: str
    site_id: str
    contract_id: str
    name: str
