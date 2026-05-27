from pydantic import BaseModel, Field


class DescriptionRequest(BaseModel):
    site: str = Field(..., min_length=1)
    contrat: str = Field(..., min_length=1)
    zone: str = Field(..., min_length=1)
    description: str = Field(..., min_length=1)


class EquipmentRow(BaseModel):
    site: str
    contrat: str
    zone: str
    equipement: str
    description: str


class InterpretResponse(BaseModel):
    rows: list[EquipmentRow]
    raw_model_output: str
