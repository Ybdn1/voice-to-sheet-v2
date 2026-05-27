from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_current_user
from app.schemas.report import DescriptionRequest, InterpretResponse
from app.services.ai_extractor import ai_extractor_service


router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("/interpret", response_model=InterpretResponse)
def interpret_description(
    payload: DescriptionRequest,
    _: dict[str, str] = Depends(get_current_user),
) -> InterpretResponse:
    try:
        rows, raw_content = ai_extractor_service.extract_rows(payload)
        return InterpretResponse(rows=rows, raw_model_output=raw_content)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Impossible de transformer la description en JSON exploitable.",
                "error": str(exc),
            },
        ) from exc
