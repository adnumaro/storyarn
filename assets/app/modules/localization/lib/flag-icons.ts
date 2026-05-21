import br from "flag-icons/flags/1x1/br.svg?url";
import bg from "flag-icons/flags/1x1/bg.svg?url";
import cn from "flag-icons/flags/1x1/cn.svg?url";
import cz from "flag-icons/flags/1x1/cz.svg?url";
import de from "flag-icons/flags/1x1/de.svg?url";
import dk from "flag-icons/flags/1x1/dk.svg?url";
import ee from "flag-icons/flags/1x1/ee.svg?url";
import es from "flag-icons/flags/1x1/es.svg?url";
import esCt from "flag-icons/flags/1x1/es-ct.svg?url";
import fi from "flag-icons/flags/1x1/fi.svg?url";
import fr from "flag-icons/flags/1x1/fr.svg?url";
import gb from "flag-icons/flags/1x1/gb.svg?url";
import gr from "flag-icons/flags/1x1/gr.svg?url";
import hr from "flag-icons/flags/1x1/hr.svg?url";
import hu from "flag-icons/flags/1x1/hu.svg?url";
import id from "flag-icons/flags/1x1/id.svg?url";
import il from "flag-icons/flags/1x1/il.svg?url";
import inFlag from "flag-icons/flags/1x1/in.svg?url";
import it from "flag-icons/flags/1x1/it.svg?url";
import jp from "flag-icons/flags/1x1/jp.svg?url";
import kr from "flag-icons/flags/1x1/kr.svg?url";
import lt from "flag-icons/flags/1x1/lt.svg?url";
import lv from "flag-icons/flags/1x1/lv.svg?url";
import my from "flag-icons/flags/1x1/my.svg?url";
import nl from "flag-icons/flags/1x1/nl.svg?url";
import no from "flag-icons/flags/1x1/no.svg?url";
import ph from "flag-icons/flags/1x1/ph.svg?url";
import pl from "flag-icons/flags/1x1/pl.svg?url";
import pt from "flag-icons/flags/1x1/pt.svg?url";
import ro from "flag-icons/flags/1x1/ro.svg?url";
import rs from "flag-icons/flags/1x1/rs.svg?url";
import ru from "flag-icons/flags/1x1/ru.svg?url";
import sa from "flag-icons/flags/1x1/sa.svg?url";
import se from "flag-icons/flags/1x1/se.svg?url";
import si from "flag-icons/flags/1x1/si.svg?url";
import sk from "flag-icons/flags/1x1/sk.svg?url";
import th from "flag-icons/flags/1x1/th.svg?url";
import tr from "flag-icons/flags/1x1/tr.svg?url";
import tw from "flag-icons/flags/1x1/tw.svg?url";
import ua from "flag-icons/flags/1x1/ua.svg?url";
import us from "flag-icons/flags/1x1/us.svg?url";
import vn from "flag-icons/flags/1x1/vn.svg?url";

const flagIconUrls: Record<string, string> = {
  br,
  bg,
  cn,
  cz,
  de,
  dk,
  ee,
  es,
  "es-ct": esCt,
  fi,
  fr,
  gb,
  gr,
  hr,
  hu,
  id,
  il,
  in: inFlag,
  it,
  jp,
  kr,
  lt,
  lv,
  my,
  nl,
  no,
  ph,
  pl,
  pt,
  ro,
  rs,
  ru,
  sa,
  se,
  si,
  sk,
  th,
  tr,
  tw,
  ua,
  us,
  vn,
};

export function flagIconUrl(flagCode: string | null | undefined): string | null {
  if (!flagCode) return null;
  return flagIconUrls[flagCode] ?? null;
}
